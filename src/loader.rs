use std::path::Path;
use std::process::{Command, Stdio};

use crate::model;

const LOADER_JS: &str = include_str!("loader.js");

const BEGIN: &str = "<<<XX_JSON_BEGIN>>>";
const END: &str = "<<<XX_JSON_END>>>";

fn json_string(s: &str) -> String {
    serde_json::Value::String(s.to_string()).to_string()
}

/**
 * Runs config through node and returns sorted, validated list of commands.
 *
 *   XX_NODE       - path to node binary (default: "node" from PATH).
 *                   Pointing it to real binary skips version manager shims (asdf: ~80ms).
 *   NODE_OPTIONS  - removed from environment of node, same as the old xx.sh did.
 *
 * stdin of node is /dev/null: stdin of xx belongs to the final script.
 */
pub fn load(config: &Path, cwd: &Path, args: &[String]) -> Result<Vec<model::Command>, String> {
    let config_str = config.to_string_lossy().to_string();

    let node = match std::env::var("XX_NODE") {
        Ok(v) if !v.trim().is_empty() => v,
        _ => "node".to_string(),
    };

    let args_json: Vec<String> = args.iter().map(|a| json_string(a)).collect();
    let ctx = format!(
        r#"{{"args":[{}],"cwd":{},"configPath":{}}}"#,
        args_json.join(","),
        json_string(&cwd.to_string_lossy()),
        json_string(&config_str),
    );

    let output = Command::new(&node)
        .arg("-e")
        .arg(LOADER_JS)
        .arg(&config_str)
        .arg(&ctx)
        .env_remove("NODE_OPTIONS")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()
        .map_err(|e| format!("can't run node >{node}< (is node installed? you can set XX_NODE): {e}"))?;

    if !output.status.success() {
        return Err(format!("loading config >{config_str}< failed"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    let json = stdout
        .rfind(BEGIN)
        .map(|i| &stdout[i + BEGIN.len()..])
        .and_then(|rest| rest.rfind(END).map(|j| &rest[..j]))
        .ok_or_else(|| format!("loader printed no result for config >{config_str}<"))?;

    model::parse(json, &config_str)
}
