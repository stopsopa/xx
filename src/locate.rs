use std::fs;
use std::path::{Path, PathBuf};

// file names accepted in each location, first found wins
const CONFIG_NAMES: [&str; 2] = ["xx.cjs", "xx.mjs"];

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
        let target = content.lines().find_map(|l| l.strip_prefix("gitdir:"))?.trim();
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
    CONFIG_NAMES.iter().map(|n| dir.join(n)).find(|p| p.is_file())
}

/**
 * Lookup order (same as the old xx.sh):
 *
 *   config                              generated script
 *   <git dir>/xx.cjs                    <git dir>/xx_generated.sh
 *   ./xx.cjs  (git dir exist)           <git dir>/xx_generated.sh
 *   ./xx.cjs  (no git dir)              ~/xx_generated.sh
 *   ~/xx.cjs                            ~/xx_generated.sh
 *
 * Err contains list of all places which were checked.
 */
pub fn locate(cwd: &Path, home: Option<&Path>) -> Result<Located, Vec<PathBuf>> {
    let git = git_dir(cwd);

    let mut checked: Vec<PathBuf> = Vec::new();

    if let Some(git) = &git {
        if let Some(config) = find_config(git) {
            return Ok(Located {
                config,
                generated: git.join(GENERATED_NAME),
            });
        }
        checked.push(git.join(CONFIG_NAMES[0]));
    }

    if let Some(config) = find_config(cwd) {
        let generated = match (&git, home) {
            (Some(git), _) => git.join(GENERATED_NAME),
            (None, Some(home)) => home.join(GENERATED_NAME),
            (None, None) => cwd.join(GENERATED_NAME),
        };
        return Ok(Located { config, generated });
    }
    checked.push(cwd.join(CONFIG_NAMES[0]));

    if let Some(home) = home {
        if let Some(config) = find_config(home) {
            return Ok(Located {
                config,
                generated: home.join(GENERATED_NAME),
            });
        }
        checked.push(home.join(CONFIG_NAMES[0]));
    }

    Err(checked)
}

/**
 * Target of --init: <git dir>/xx.cjs, or ./xx.cjs when there is no git dir.
 */
pub fn init_target(cwd: &Path) -> PathBuf {
    match git_dir(cwd) {
        Some(git) => git.join(CONFIG_NAMES[0]),
        None => cwd.join(CONFIG_NAMES[0]),
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

    #[test]
    fn nothing_found_lists_checked_places() {
        let d = tmp("none");
        let err = locate(&d.join("cwd"), Some(&d.join("home"))).unwrap_err();
        assert_eq!(err, vec![d.join("cwd/xx.cjs"), d.join("home/xx.cjs")]);
    }

    #[test]
    fn git_config_wins() {
        let d = tmp("git");
        fs::create_dir_all(d.join("cwd/.git")).unwrap();
        fs::write(d.join("cwd/.git/xx.cjs"), "").unwrap();
        fs::write(d.join("cwd/xx.cjs"), "").unwrap();
        fs::write(d.join("home/xx.cjs"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home"))).unwrap();
        assert_eq!(l.config, d.join("cwd/.git/xx.cjs"));
        assert_eq!(l.generated, d.join("cwd/.git/xx_generated.sh"));
    }

    #[test]
    fn local_config_with_and_without_git() {
        let d = tmp("local");
        fs::write(d.join("cwd/xx.cjs"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home"))).unwrap();
        assert_eq!(l.config, d.join("cwd/xx.cjs"));
        assert_eq!(l.generated, d.join("home/xx_generated.sh"));

        fs::create_dir_all(d.join("cwd/.git")).unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home"))).unwrap();
        assert_eq!(l.generated, d.join("cwd/.git/xx_generated.sh"));
    }

    #[test]
    fn home_config_is_last() {
        let d = tmp("home");
        fs::create_dir_all(d.join("cwd/.git")).unwrap();
        fs::write(d.join("home/xx.cjs"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home"))).unwrap();
        assert_eq!(l.config, d.join("home/xx.cjs"));
        assert_eq!(l.generated, d.join("home/xx_generated.sh"));
    }

    #[test]
    fn git_file_points_to_real_git_dir() {
        let d = tmp("worktree");
        fs::create_dir_all(d.join("real")).unwrap();
        fs::write(d.join("cwd/.git"), "gitdir: ../real\n").unwrap();
        fs::write(d.join("cwd/xx.cjs"), "").unwrap();
        let l = locate(&d.join("cwd"), Some(&d.join("home"))).unwrap();
        assert_eq!(l.generated, d.join("cwd/../real/xx_generated.sh"));
    }
}
