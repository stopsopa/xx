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
    fn tmp_generated_depends_on_cwd() {
        let a = tmp_generated(Path::new("/t"), 501, Path::new("/a"));
        let b = tmp_generated(Path::new("/t"), 501, Path::new("/b"));
        assert_ne!(a, b);
        assert_eq!(a, tmp_generated(Path::new("/t"), 501, Path::new("/a")));
        assert!(a.starts_with("/t/xx-501"));
        assert_eq!(a.extension().unwrap(), "sh");
    }
}
