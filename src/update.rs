use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::{fetch, home, is_url, locate, menu, VERSION};

pub const RELEASES: &str = "https://github.com/stopsopa/xx/releases";
pub const ENV_RELEASES: &str = "XX_RELEASES";

// set by xx.sh for "xx --update": path of xx.sh itself, the binary has no other way to know it
const ENV_SH_PATH: &str = "__XX_SH_PATH";

const SUMS: &str = "SHA256SUMS.txt";
const WRAPPER: &str = "xx.sh";

/**
 * Name of the binary of this platform among files of a release.
 * Known at compile time: the binary which is running is the best proof of what works here.
 */
pub fn asset() -> Option<&'static str> {
    if cfg!(all(target_os = "macos", target_arch = "aarch64")) {
        Some("xx-darwin-arm64")
    } else if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
        Some("xx-linux-x64")
    } else if cfg!(all(target_os = "linux", target_arch = "aarch64")) {
        Some("xx-linux-arm64")
    } else {
        None
    }
}

// url or local directory ("~/" expanded), without "/" at the end
pub fn releases() -> String {
    let source = match std::env::var(ENV_RELEASES) {
        Ok(u) if !u.trim().is_empty() => u.trim().to_string(),
        _ => RELEASES.to_string(),
    };
    let source = if is_url(&source) {
        source
    } else {
        locate::expand_tilde(&source, home().as_deref())
    };
    source.trim_end_matches('/').to_string()
}

// tag goes to urls and paths, nothing surprising is allowed in it
pub fn valid_tag(tag: &str) -> bool {
    !tag.is_empty()
        && tag.len() <= 64
        && !tag.starts_with(['.', '-'])
        && tag
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-' || b == b'_')
}

// "https://github.com/stopsopa/xx/releases/tag/v0.1.0" -> "v0.1.0"
pub fn tag_from_redirect(location: &str) -> Option<String> {
    let tag = location.trim().rsplit_once("/tag/")?.1;
    let tag = tag.split(['?', '#', '/']).next()?;
    valid_tag(tag).then(|| tag.to_string())
}

/**
 * Tag of the latest release:
 *
 *   url             - <releases>/latest redirects to <releases>/tag/<tag> (github does that, only
 *                     published releases count, no drafts, no api and its rate limits)
 *   local directory - content of file <releases>/latest
 */
fn latest(releases: &str) -> Result<String, String> {
    if !is_url(releases) {
        let file = Path::new(releases).join("latest");
        let tag = fs::read_to_string(&file)
            .map_err(|e| format!("can't read file >{}<: {e}", file.display()))?;
        let tag = tag.trim().to_string();
        if !valid_tag(&tag) {
            return Err(format!(
                "file >{}< doesn't contain a tag: >{tag}<",
                file.display()
            ));
        }
        return Ok(tag);
    }

    let url = format!("{releases}/latest");

    let run = |program: &str, args: &[&str]| {
        Command::new(program)
            .args(args)
            .arg(&url)
            .stdin(Stdio::null())
            .output()
            .ok()
    };

    // curl prints where it was redirected to, wget prints headers of the answer on stderr
    let answer = match run("curl", &["-sS", "-o", "/dev/null", "-w", "%{redirect_url}"]) {
        Some(out) => String::from_utf8_lossy(&out.stdout).to_string(),
        None => {
            let out = run("wget", &["--max-redirect=0", "-S", "-O", "/dev/null"])
                .ok_or_else(|| format!("neither curl nor wget found, can't check >{url}<"))?;
            String::from_utf8_lossy(&out.stderr)
                .lines()
                .filter_map(|l| l.trim().strip_prefix("Location:"))
                .map(|l| l.split_whitespace().next().unwrap_or("").to_string())
                .next()
                .unwrap_or_default()
        }
    };

    tag_from_redirect(&answer).ok_or_else(|| {
        format!(
            "can't find out the latest release: >{url}< was expected to redirect to .../tag/<tag>, got >{}<\n  (no network? no release published yet?)",
            answer.trim()
        )
    })
}

// "<sha256>  <name>" lines of SHA256SUMS.txt
pub fn checksum_of(sums: &str, name: &str) -> Option<String> {
    sums.lines().find_map(|line| {
        let mut parts = line.split_whitespace();
        let hash = parts.next()?;
        let file = parts.next()?.trim_start_matches('*');
        (file == name && hash.len() == 64 && hash.bytes().all(|b| b.is_ascii_hexdigit()))
            .then(|| hash.to_ascii_lowercase())
    })
}

fn sha256(file: &Path) -> Result<String, String> {
    let run = |program: &str, args: &[&str]| {
        Command::new(program)
            .args(args)
            .arg(file)
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .ok()
            .filter(|o| o.status.success())
    };
    let out = run("sha256sum", &[])
        .or_else(|| run("shasum", &["-a", "256"]))
        .ok_or_else(|| "neither sha256sum nor shasum found, can't verify checksums".to_string())?;
    String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .next()
        .map(|h| h.to_ascii_lowercase())
        .ok_or_else(|| format!("can't compute sha256 of >{}<", file.display()))
}

// shells the pair is tested in: /bin/bash always, and the shell of the user when it is not bash
fn shells() -> Vec<String> {
    let mut list = vec!["/bin/bash".to_string()];
    if let Ok(shell) = std::env::var("SHELL") {
        if shell.ends_with("/zsh") && Path::new(&shell).is_file() {
            list.push(shell);
        }
    }
    list
}

/**
 * The test of the pair: the wrapper is sourced in a real shell with XX_BIN pointing to the binary and
 * asked for --version. To answer the wrapper has to load, accept the binary (md5 embedded in the
 * wrapper has to match) and the binary has to be executable on this machine. Both have to
 * report the expected version.
 */
fn smoke(sh: &Path, bin: &Path, tag: &str) -> Result<(), String> {
    let expected = format!("xx.sh {tag}\nxx {tag}");
    for shell in shells() {
        let mut cmd = Command::new(&shell);
        if shell.ends_with("/zsh") {
            // no startup files
            cmd.arg("-f");
        }
        let out = cmd
            .args(["-c", "source \"${1}\" --version", "xx"])
            .arg(sh)
            .env("XX_BIN", bin)
            .stdin(Stdio::null())
            .output()
            .map_err(|e| format!("can't start >{shell}<: {e}"))?;
        let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if !out.status.success() || stdout != expected {
            return Err(format!(
                "test of the pair failed in >{shell}<:\n    XX_BIN=\"{}\" source \"{}\" --version\n  expected output:\n{}\n  exit code: {}\n  stdout:\n{}\n  stderr:\n{}",
                bin.display(),
                sh.display(),
                indent(&expected),
                out.status
                    .code()
                    .map(|c| c.to_string())
                    .unwrap_or_else(|| "killed by signal".to_string()),
                indent(&stdout),
                indent(String::from_utf8_lossy(&out.stderr).trim()),
            ));
        }
    }
    Ok(())
}

fn indent(text: &str) -> String {
    text.lines()
        .map(|l| format!("    {l}"))
        .collect::<Vec<_>>()
        .join("\n")
}

fn sibling(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(format!(".{suffix}-{}", std::process::id()));
    path.with_file_name(name)
}

struct Pair {
    sh: PathBuf,
    bin: PathBuf,
}

/**
 * Everything what touches the disk. Both files are replaced in one go:
 *
 *   1. new files are written next to the installed ones (<file>.new-<pid>), so the final rename
 *      stays on one filesystem and is atomic
 *   2. checksums from SHA256SUMS.txt of the release are verified
 *   3. the new pair is tested (smoke) - until now nothing installed was touched
 *   4. installed files are copied aside (<file>.old-<pid>)
 *   5. rename, rename
 *   6. the installed pair is tested again, on any failure in 5 or 6 both old files are put back
 *
 * Returns Err with nothing changed (or everything restored).
 */
fn install(releases: &str, tag: &str, asset: &str, installed: &Pair) -> Result<(), String> {
    let new = Pair {
        sh: sibling(&installed.sh, "new"),
        bin: sibling(&installed.bin, "new"),
    };
    let old = Pair {
        sh: sibling(&installed.sh, "old"),
        bin: sibling(&installed.bin, "old"),
    };

    let result = install_inner(releases, tag, asset, installed, &new, &old);

    for file in [&new.sh, &new.bin, &old.sh, &old.bin] {
        let _ = fs::remove_file(file);
    }

    result
}

fn install_inner(
    releases: &str,
    tag: &str,
    asset: &str,
    installed: &Pair,
    new: &Pair,
    old: &Pair,
) -> Result<(), String> {
    let base = Path::new("/");
    let location = |name: &str| format!("{releases}/download/{tag}/{name}");
    let download = |name: &str| {
        eprintln!("  downloading {}", location(name));
        fetch(&location(name), base).map_err(|e| {
            format!("{e}\n  is >{tag}< a published release with all files? see {releases}")
        })
    };

    let sums = String::from_utf8_lossy(&download(SUMS)?).to_string();

    for (name, target, mode) in [(asset, &new.bin, 0o755), (WRAPPER, &new.sh, 0o644)] {
        let expected = checksum_of(&sums, name)
            .ok_or_else(|| format!("{} doesn't list sha256 of >{name}<", location(SUMS)))?;
        let content = download(name)?;
        fs::write(target, content)
            .and_then(|_| fs::set_permissions(target, fs::Permissions::from_mode(mode)))
            .map_err(|e| {
                format!(
                    "can't write >{}<: {e}\n  the directory has to be writable for the update",
                    target.display()
                )
            })?;
        let found = sha256(target)?;
        if found != expected {
            return Err(format!(
                "checksum of downloaded >{name}< doesn't match (broken download?)\n  sha256 of the file : {found}\n  {SUMS}     : {expected}"
            ));
        }
        eprintln!("  checksum ok: {name}");
    }

    smoke(&new.sh, &new.bin, tag)
        .map_err(|e| format!("downloaded files don't work together, nothing was changed.\n  {e}"))?;
    eprintln!("  test ok: downloaded xx.sh works with downloaded binary");

    // the wrapper keeps permissions it has now
    if let Ok(meta) = fs::metadata(&installed.sh) {
        let _ = fs::set_permissions(&new.sh, meta.permissions());
    }

    for (from, to) in [(&installed.sh, &old.sh), (&installed.bin, &old.bin)] {
        fs::copy(from, to).map_err(|e| {
            format!(
                "can't copy >{}< to >{}<: {e}",
                from.display(),
                to.display()
            )
        })?;
    }

    let restore = |reason: String| {
        let sh = fs::rename(&old.sh, &installed.sh);
        let bin = fs::rename(&old.bin, &installed.bin);
        match (sh, bin) {
            (Ok(_), Ok(_)) => format!("{reason}\n  previous version was restored"),
            (sh, bin) => format!(
                "{reason}\n  AND restoring previous version failed (xx.sh: {sh:?}, binary: {bin:?}),\n  install both files again: {RELEASES}"
            ),
        }
    };

    if let Err(e) = fs::rename(&new.sh, &installed.sh) {
        // nothing replaced yet
        return Err(format!(
            "can't replace >{}<: {e}",
            installed.sh.display()
        ));
    }
    if let Err(e) = fs::rename(&new.bin, &installed.bin) {
        return Err(restore(format!(
            "can't replace >{}<: {e}",
            installed.bin.display()
        )));
    }

    if let Err(e) = smoke(&installed.sh, &installed.bin, tag) {
        return Err(restore(format!("installed files don't work together.\n  {e}")));
    }
    eprintln!("  test ok: installed xx.sh works with installed binary");

    Ok(())
}

/**
 * xx --update            update to the latest release
 * xx --update <tag>      install given release (also older one)
 * xx --update --check    only say if there is something newer
 */
pub fn update(args: &[String]) -> Result<(), String> {
    let (check, requested) = match args {
        [] => (false, None),
        [one] if one == "--check" => (true, None),
        [one] if valid_tag(one) => (false, Some(one.clone())),
        _ => {
            return Err(format!(
                "wrong arguments >{}<, usage:\n  xx --update            update to the latest release\n  xx --update <tag>      install given release, e.g. xx --update v0.1.0\n  xx --update --check    only check if there is a newer release",
                args.join(" ")
            ))
        }
    };

    if VERSION == "dev" {
        return Err(format!(
            "this binary is a local build (version >dev<), not a release, there is nothing to update.\n  Releases: {RELEASES}"
        ));
    }

    let asset = asset().ok_or_else(|| {
        format!("there are no released binaries for this platform, see {RELEASES}")
    })?;

    let releases = releases();

    let (tag, what) = match requested {
        Some(tag) => (tag, "requested"),
        None => (latest(&releases)?, "latest"),
    };

    println!("installed: {VERSION}");
    println!("{what}: {tag}");

    if tag == VERSION {
        println!("xx is up to date");
        return Ok(());
    }

    if check {
        println!("to install it: xx --update");
        return Ok(());
    }

    let sh = std::env::var(ENV_SH_PATH)
        .ok()
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| {
            "path of xx.sh is not known: --update has to be called through xx.sh (xx --update), not by executing the binary directly".to_string()
        })?;
    if !sh.is_absolute() || !sh.is_file() {
        return Err(format!(
            "xx.sh was expected at >{}<, it is not a file",
            sh.display()
        ));
    }

    let bin = std::env::var("XX_BIN")
        .ok()
        .filter(|p| !p.trim().is_empty())
        .map(|p| PathBuf::from(locate::expand_tilde(p.trim(), home().as_deref())))
        .ok_or_else(|| "env var XX_BIN is not defined".to_string())?;
    if !bin.is_absolute() || !bin.is_file() {
        return Err(format!(
            "XX_BIN=>{}< - it has to be absolute path of existing file",
            bin.display()
        ));
    }

    println!("files to replace:");
    println!("  {}", sh.display());
    println!("  {}", bin.display());

    if std::env::var("XX_CONFIRM").as_deref() != Ok("false") {
        let mut term = menu::open_term().map_err(|e| {
            format!("{e}\n  update needs confirmation and there is no terminal, use XX_CONFIRM=false")
        })?;
        let answer = menu::ask(term.as_mut(), "Update xx?", &format!("{VERSION} -> {tag}"));
        drop(term);
        if answer != Some(true) {
            println!("nothing changed");
            return Ok(());
        }
    }

    install(&releases, &tag, asset, &Pair { sh, bin })?;

    println!("xx updated: {VERSION} -> {tag}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tags() {
        assert!(valid_tag("v0.1.0"));
        assert!(valid_tag("1.2.3-rc.1"));
        assert!(!valid_tag(""));
        assert!(!valid_tag("--check"));
        assert!(!valid_tag("../v1"));
        assert!(!valid_tag("v1 0"));
        assert!(!valid_tag(".."));
    }

    #[test]
    fn redirect() {
        assert_eq!(
            tag_from_redirect("https://github.com/stopsopa/xx/releases/tag/v0.1.0\n").as_deref(),
            Some("v0.1.0")
        );
        assert_eq!(
            tag_from_redirect("https://example.com/releases/tag/v2.0.0?x=1").as_deref(),
            Some("v2.0.0")
        );
        // no release at all: github redirects to the list of releases
        assert_eq!(tag_from_redirect("https://github.com/stopsopa/xx/releases"), None);
        assert_eq!(tag_from_redirect(""), None);
    }

    #[test]
    fn checksums() {
        let h = "b9e882d2f1a0fc687bd4922b9452da297f813fed970fbfcba2bd7f803ca90d2b";
        let sums = format!("{h}  xx-darwin-arm64\n{}  *xx.sh\nshort  xx-linux-x64\n", h.to_uppercase());
        assert_eq!(checksum_of(&sums, "xx-darwin-arm64").as_deref(), Some(h));
        assert_eq!(checksum_of(&sums, "xx.sh").as_deref(), Some(h));
        assert_eq!(checksum_of(&sums, "xx-linux-x64"), None);
        assert_eq!(checksum_of(&sums, "xx"), None);
    }
}
