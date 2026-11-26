use std::fs;
use std::path::{Path, PathBuf};

// extensions accepted in each location, first found wins: xx.ts, xx.js, xx.mjs, xx.cjs
pub const EXTENSIONS: [&str; 4] = ["ts", "js", "mjs", "cjs"];

pub const GENERATED_NAME: &str = "xx_generated.sh";

#[derive(Debug, PartialEq)]
pub struct Located {
    // config with list of commands
    pub config: PathBuf,
    // where script of selected command will be written
    pub generated: PathBuf,
}

/**
 * Finds git directory of given directory (not walking up).
 *
 *   .git is a directory        -> that directory
 *   .git is a file (worktree,
 *   submodule: "gitdir: path") -> the path from the file
 */
pub fn git_dir(cwd: &Path) -> Option<PathBuf> {
    let dot_git = cwd.join(".git");

    if dot_git.is_dir() {
        return Some(dot_git);
    }

    if dot_git.is_file() {
        let content = fs::read_to_string(&dot_git).ok()?;
        let target = content
            .lines()
            .find_map(|l| l.strip_prefix("gitdir:"))?
            .trim();
        let path = Path::new(target);
        let resolved = if path.is_absolute() {
            path.to_path_buf()
        } else {
            cwd.join(path)
        };
        if resolved.is_dir() {
            return Some(resolved);
        }
    }

    None
}

/**
 * "~/something" -> "<home>/something", "~" -> "<home>". Anything else is returned untouched.
 *
 * Paths given in env vars can start with ~/ : the shell doesn't expand it inside of quotes
 * (export XX_NODE_BINARY="~/bin/node"), so xx does.
 */
pub fn expand_tilde(value: &str, home: Option<&Path>) -> String {
    let Some(home) = home else {
        return value.to_string();
    };
    if value == "~" {
        return home.to_string_lossy().to_string();
    }
    match value.strip_prefix("~/") {
        Some(rest) => home.join(rest).to_string_lossy().to_string(),
        None => value.to_string(),
    }
}

fn find_config(dir: &Path) -> Option<PathBuf> {
    EXTENSIONS
        .iter()
        .map(|e| dir.join(format!("xx.{e}")))
        .find(|p| p.is_file())
}

// FNV-1a 64 bit: stable between runs and versions, which std hasher doesn't promise
fn hash(text: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in text {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

/**
 * Where the script goes when there is no git directory:
 *
 *   <tmp>/xx-<uid>/<hash of cwd>.sh
 *
 * One file per directory, so xx running in two different directories at the same time
 * can't overwrite each other's script (that was the problem with single ~/xx_generated.sh).
 */
pub fn tmp_generated(tmp: &Path, uid: u32, cwd: &Path) -> PathBuf {
    use std::os::unix::ffi::OsStrExt;
    tmp.join(format!("xx-{uid}"))
        .join(format!("{:016x}.sh", hash(cwd.as_os_str().as_bytes())))
}

/**
 * The same for config given with --config / XX_CONFIG: the file depends on the directory xx was
 * called in AND on the config, so the same config used in two directories at once, or two
 * configs used in one directory, never share the file. Always in tmp: .git of the current
 * directory belongs to another project than the config.
 */
pub fn tmp_generated_explicit(tmp: &Path, uid: u32, cwd: &Path, config: &Path) -> PathBuf {
    use std::os::unix::ffi::OsStrExt;
    let mut key = cwd.as_os_str().as_bytes().to_vec();
    key.push(0);
    key.extend_from_slice(config.as_os_str().as_bytes());
    tmp.join(format!("xx-{uid}"))
        .join(format!("{:016x}.sh", hash(&key)))
}

// "/a/./b/../c" -> "/a/c", without touching the disk (symlinks stay as they were written)
pub fn normalize(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/**
 * Config given with --config / XX_CONFIG. No other place is searched, no fallback.
 *
 *   file       - any name, extension has to be one of EXTENSIONS (it decides how node loads it)
 *   directory  - xx.ts, xx.js, xx.mjs, xx.cjs in it (not in its .git)
 *
 * Relative path is resolved against cwd, "~/" at the beginning means home.
 * Returns absolute path of the config, Err is a message with the absolute path in it.
 */
pub fn explicit(value: &str, cwd: &Path, home: Option<&Path>) -> Result<PathBuf, String> {
    let path = normalize(&cwd.join(expand_tilde(value, home)));

    if path.is_dir() {
        return find_config(&path).ok_or_else(|| {
            let names: Vec<String> = EXTENSIONS.iter().map(|e| format!("xx.{e}")).collect();
            format!(
                "directory >{}< has no config in it, looked for {}",
                path.display(),
                names.join(", ")
            )
        });
    }

    if !path.is_file() {
        return Err(format!(
            "config >{}< doesn't exist (it has to be a file or a directory)",
            path.display()
        ));
    }

    let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("");
    if !EXTENSIONS.contains(&extension) {
        return Err(format!(
            "config >{}< has unsupported extension >{extension}<, allowed: {}\n  (the extension decides how node loads the file)",
            path.display(),
            EXTENSIONS.map(|e| format!(".{e}")).join(", ")
        ));
    }

    Ok(path)
}

/**
 * Lookup order, in every directory: xx.ts, xx.js, xx.mjs, xx.cjs
 *
 *   config                              generated script
 *   <git dir>/xx.*                      <git dir>/xx_generated.sh
 *   ./xx.*    (git dir exist)           <git dir>/xx_generated.sh
 *   ./xx.*    (no git dir)              fallback (see tmp_generated)
 *   ~/xx.*                              fallback
 *
 * Err contains list of all directories which were checked.
 */
pub fn locate(cwd: &Path, home: Option<&Path>, fallback: &Path) -> Result<Located, Vec<PathBuf>> {
    let git = git_dir(cwd);

    let mut checked: Vec<PathBuf> = Vec::new();

    if let Some(git) = &git {
        if let Some(config) = find_config(git) {
            return Ok(Located {
                config,
                generated: git.join(GENERATED_NAME),
            });
        }
        checked.push(git.clone());
    }

    if let Some(config) = find_config(cwd) {
        let generated = match &git {
            Some(git) => git.join(GENERATED_NAME),
            None => fallback.to_path_buf(),
        };
        return Ok(Located { config, generated });
    }
    checked.push(cwd.to_path_buf());

    if let Some(home) = home {
        if home != cwd {
            if let Some(config) = find_config(home) {
                return Ok(Located {
                    config,
                    generated: fallback.to_path_buf(),
                });
            }
            checked.push(home.to_path_buf());
        }
    }

    Err(checked)
}

/**
 * Target of --init: <git dir>/xx.<ext>, or ./xx.<ext> when there is no git dir.
 */
pub fn init_target(cwd: &Path, ext: &str) -> PathBuf {
    let name = format!("xx.{ext}");
    match git_dir(cwd) {
        Some(git) => git.join(name),
        None => cwd.join(name),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("xx-locate-{}-{}", std::process::id(), name));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("cwd")).unwrap();
        fs::create_dir_all(dir.join("home")).unwrap();
        dir
    }

    fn fb() -> PathBuf {
        PathBuf::from("/fallback/script.sh")
    }

    #[test]
    fn nothing_found_lists_checked_places() {
        let d = tmp("none");
        let err = locate(&d.join("cwd"), Some(&d.join("home")), &fb()).unwrap_err();
        assert_eq!(err, vec![d.join("cwd"), d.join("home")]);
    }

    #[test]
    fn git_config_wins() {
        let d = tmp("git");
        fs::create_dir_all(d.join("cwd/.git")).unwrap();
        fs::write(d.join("cwd/.git/xx.cjs"), "").unwrap();
        fs::write(d.join("cwd/xx.ts"), "").unwrap();
        fs::write(d.join("home/xx.ts"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home")), &fb()).unwrap();
        assert_eq!(l.config, d.join("cwd/.git/xx.cjs"));
        assert_eq!(l.generated, d.join("cwd/.git/xx_generated.sh"));
    }

    #[test]
    fn extensions_priority() {
        let d = tmp("ext");
        let cwd = d.join("cwd");
        for (i, ext) in EXTENSIONS.iter().enumerate().rev() {
            fs::write(cwd.join(format!("xx.{ext}")), "").unwrap();
            let l = locate(&cwd, None, &fb()).unwrap();
            assert_eq!(l.config, cwd.join(format!("xx.{}", EXTENSIONS[i])));
        }
        assert_eq!(EXTENSIONS, ["ts", "js", "mjs", "cjs"]);
    }

    #[test]
    fn local_config_with_and_without_git() {
        let d = tmp("local");
        fs::write(d.join("cwd/xx.cjs"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home")), &fb()).unwrap();
        assert_eq!(l.config, d.join("cwd/xx.cjs"));
        assert_eq!(l.generated, fb());

        fs::create_dir_all(d.join("cwd/.git")).unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home")), &fb()).unwrap();
        assert_eq!(l.generated, d.join("cwd/.git/xx_generated.sh"));
    }

    #[test]
    fn home_config_is_last() {
        let d = tmp("home");
        fs::create_dir_all(d.join("cwd/.git")).unwrap();
        fs::write(d.join("home/xx.js"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home")), &fb()).unwrap();
        assert_eq!(l.config, d.join("home/xx.js"));
        assert_eq!(l.generated, fb());
    }

    #[test]
    fn git_file_points_to_real_git_dir() {
        let d = tmp("worktree");
        fs::create_dir_all(d.join("real")).unwrap();
        fs::write(d.join("cwd/.git"), "gitdir: ../real\n").unwrap();
        fs::write(d.join("cwd/xx.cjs"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home")), &fb()).unwrap();
        assert_eq!(l.generated, d.join("cwd/../real/xx_generated.sh"));
    }

    #[test]
    fn tilde() {
        let home = Path::new("/home/me");
        assert_eq!(expand_tilde("~/bin/node", Some(home)), "/home/me/bin/node");
        assert_eq!(expand_tilde("~", Some(home)), "/home/me");
        assert_eq!(expand_tilde("/abs/~/x", Some(home)), "/abs/~/x");
        assert_eq!(expand_tilde("~other/x", Some(home)), "~other/x");
        assert_eq!(expand_tilde("rel/x", Some(home)), "rel/x");
        assert_eq!(expand_tilde("~/x", None), "~/x");
    }

    #[test]
    fn explicit_config() {
        let d = tmp("explicit");
        let cwd = d.join("cwd");
        let home = d.join("home");
        fs::create_dir_all(d.join("tools/.git")).unwrap();
        fs::write(d.join("tools/menu.ts"), "").unwrap();
        fs::write(d.join("tools/.git/xx.ts"), "").unwrap();
        fs::write(d.join("tools/notes.txt"), "").unwrap();
        fs::write(home.join("h.cjs"), "").unwrap();

        // file: absolute, relative to cwd, ~/
        let abs = d.join("tools/menu.ts");
        assert_eq!(explicit(abs.to_str().unwrap(), &cwd, Some(&home)).unwrap(), abs);
        assert_eq!(explicit("../tools/./menu.ts", &cwd, Some(&home)).unwrap(), abs);
        assert_eq!(explicit("~/h.cjs", &cwd, Some(&home)).unwrap(), home.join("h.cjs"));

        // directory: only xx.* directly in it, .git of it is not searched
        let e = explicit("../tools", &cwd, Some(&home)).unwrap_err();
        assert!(e.contains("has no config in it"), "{e}");
        assert!(e.contains(d.join("tools").to_str().unwrap()), "{e}");
        fs::write(d.join("tools/xx.mjs"), "").unwrap();
        fs::write(d.join("tools/xx.cjs"), "").unwrap();
        assert_eq!(explicit("../tools", &cwd, Some(&home)).unwrap(), d.join("tools/xx.mjs"));

        let e = explicit("nothing.ts", &cwd, Some(&home)).unwrap_err();
        assert!(e.contains(cwd.join("nothing.ts").to_str().unwrap()), "{e}");
        assert!(e.contains("doesn't exist"), "{e}");

        let e = explicit("../tools/notes.txt", &cwd, Some(&home)).unwrap_err();
        assert!(e.contains("unsupported extension >txt<"), "{e}");
    }

    #[test]
    fn tmp_generated_explicit_depends_on_cwd_and_config() {
        let t = Path::new("/t");
        let a = tmp_generated_explicit(t, 501, Path::new("/a"), Path::new("/c/xx.ts"));
        assert_ne!(a, tmp_generated_explicit(t, 501, Path::new("/b"), Path::new("/c/xx.ts")));
        assert_ne!(a, tmp_generated_explicit(t, 501, Path::new("/a"), Path::new("/d/xx.ts")));
        assert_ne!(a, tmp_generated(t, 501, Path::new("/a")));
        assert_eq!(a, tmp_generated_explicit(t, 501, Path::new("/a"), Path::new("/c/xx.ts")));
        assert!(a.starts_with("/t/xx-501"));
    }

    #[test]
    fn tmp_generated_depends_on_cwd() {
        let a = tmp_generated(Path::new("/t"), 501, Path::new("/a"));
        let b = tmp_generated(Path::new("/t"), 501, Path::new("/b"));
        assert_ne!(a, b);
        assert_eq!(a, tmp_generated(Path::new("/t"), 501, Path::new("/a")));
        assert!(a.starts_with("/t/xx-501"));
        assert_eq!(a.extension().unwrap(), "sh");
    }
}
