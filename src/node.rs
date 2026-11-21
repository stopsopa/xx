use std::path::Path;
use std::process::{Command, Stdio};

pub const ENV_BINARY: &str = "XX_NODE_BINARY";
pub const ENV_OPTIONS: &str = "XX_NODE_OPTIONS";

const HOW_TO_SET: &str = "
  It has to contain absolute path to node binary, the real one, not a shim of a version manager
  (\"~/\" at the beginning means home directory).
  Add to ~/.bashrc or ~/.zshrc, e.g.:

    export XX_NODE_BINARY=\"/usr/local/bin/node\"

  to find out the path of node you are using right now:

    node -e 'console.log(process.execPath)'";

/**
 * node which passed the check
 */
pub struct Node {
    pub path: String,
    // as printed by node --version, e.g. "v24.12.0"
    pub version: String,
}

impl Node {
    // (major, minor)
    pub fn major_minor(&self) -> Option<(u32, u32)> {
        let mut parts = self.version.trim_start_matches('v').split('.');
        let major = parts.next()?.parse().ok()?;
        let minor = parts.next()?.parse().ok()?;
        Some((major, minor))
    }
}

/**
 * Every node process started by xx is created here.
 *
 *   XX_NODE_OPTIONS not empty             -> NODE_OPTIONS of the node process is set to its value
 *   XX_NODE_OPTIONS not defined or empty  -> NODE_OPTIONS is left as it is in the environment
 *
 * Empty means "not defined", like in the rest of XX_* variables. To give node empty NODE_OPTIONS
 * (to hide the one from the shell) use a value with just a space: XX_NODE_OPTIONS=" "
 */
pub fn command(path: &str) -> Command {
    let mut cmd = Command::new(path);
    if let Some(options) = options() {
        cmd.env("NODE_OPTIONS", options);
    }
    cmd
}

// value of XX_NODE_OPTIONS when it is in use (defined and not empty)
pub fn options() -> Option<std::ffi::OsString> {
    std::env::var_os(ENV_OPTIONS).filter(|o| !o.is_empty())
}

fn looks_like_version(text: &str) -> bool {
    let mut parts = text.strip_prefix('v').unwrap_or("").split('.');
    let number = |p: Option<&str>| {
        p.map(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
            .unwrap_or(false)
    };
    number(parts.next()) && number(parts.next()) && parts.next().is_some()
}

/**
 * Executed on every run of xx, before anything else:
 *
 *   1. XX_NODE_BINARY has to be defined ("~/" at the beginning means home directory)
 *   2. has to point to existing file
 *   3. "<file> --version" has to answer like node does: vMAJOR.MINOR.PATCH
 */
pub fn resolve(home: Option<&Path>) -> Result<Node, String> {
    let path = match std::env::var(ENV_BINARY) {
        Ok(v) if !v.trim().is_empty() => crate::locate::expand_tilde(v.trim(), home),
        _ => {
            return Err(format!(
                "env var {ENV_BINARY} is not defined, xx needs node to load the config (xx.ts, xx.js, xx.mjs, xx.cjs).\n{HOW_TO_SET}"
            ))
        }
    };

    if !Path::new(&path).is_file() {
        return Err(format!(
            "{ENV_BINARY}=>{path}< - file doesn't exist (or it is not a file).\n{HOW_TO_SET}"
        ));
    }

    let output = command(&path)
        .arg("--version")
        .stdin(Stdio::null())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| {
            format!(
                "{ENV_BINARY}=>{path}< - can't execute it (is it executable?): {e}\n{HOW_TO_SET}"
            )
        })?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();

    if !output.status.success() || !looks_like_version(&stdout) {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let node_options = match std::env::var("NODE_OPTIONS") {
            Ok(v) => format!(">{v}<"),
            Err(_) => "not defined".to_string(),
        };
        let xx_node_options = match std::env::var(ENV_OPTIONS) {
            Ok(v) => format!(">{v}<"),
            Err(_) => "not defined".to_string(),
        };
        return Err(format!(
            "{ENV_BINARY}=>{path}< - it doesn't look like node: \"{path} --version\" was expected to print something like >v24.1.0<
  exit code: {}
  stdout:    >{stdout}<
  stderr:    >{stderr}<
  NODE_OPTIONS:    {node_options}
  {ENV_OPTIONS}: {xx_node_options} (when not empty it replaces NODE_OPTIONS for node started by xx)
{HOW_TO_SET}",
            output
                .status
                .code()
                .map(|c| c.to_string())
                .unwrap_or_else(|| "killed by signal".to_string()),
        ));
    }

    Ok(Node {
        path,
        version: stdout,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_shape() {
        assert!(looks_like_version("v24.12.0"));
        assert!(looks_like_version("v22.18.0-nightly2025"));
        assert!(!looks_like_version("24.12.0"));
        assert!(!looks_like_version("--version"));
        assert!(!looks_like_version("v24"));
        assert!(!looks_like_version(""));
    }

    #[test]
    fn major_minor() {
        let n = Node {
            path: String::new(),
            version: "v22.18.1".to_string(),
        };
        assert_eq!(n.major_minor(), Some((22, 18)));
    }
}
