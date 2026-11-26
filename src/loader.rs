use std::path::Path;
use std::process::Stdio;

use crate::model;
use crate::node::{self, Node};

const LOADER_JS: &str = include_str!("loader.js");

const BEGIN: &str = "<<<XX_JSON_BEGIN>>>";
const END: &str = "<<<XX_JSON_END>>>";

fn json_string(s: &str) -> String {
    serde_json::Value::String(s.to_string()).to_string()
}

/**
 * Runs config through node and returns sorted, validated list of commands.
 *
 * node is the one from XX_NODE_BINARY, already checked (see node.rs).
 * stdin of node is /dev/null: stdin of xx belongs to the final script.
 */
pub fn load(
    node: &Node,
    config: &Path,
    cwd: &Path,
    args: &[String],
) -> Result<Vec<model::Command>, String> {
    let config_str = config.to_string_lossy().to_string();

    let args_json: Vec<String> = args.iter().map(|a| json_string(a)).collect();
    let config_dir = config
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();
    let ctx = format!(
        r#"{{"args":[{}],"cwd":{},"configPath":{},"configDir":{}}}"#,
        args_json.join(","),
        json_string(&cwd.to_string_lossy()),
        json_string(&config_str),
        json_string(&config_dir),
    );

    let output = node::command(&node.path)
        .arg("-e")
        .arg(LOADER_JS)
        .arg(&config_str)
        .arg(&ctx)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()
        .map_err(|e| format!("can't run node >{}<: {e}", node.path))?;

    if !output.status.success() {
        let mut message = format!(
            "loading config >{config_str}< failed (node {} >{}<)",
            node.version, node.path
        );
        // .ts is executed by node itself, old node can't do that
        if config.extension().and_then(|e| e.to_str()) == Some("ts") {
            if let Some(v) = node.major_minor() {
                if v < (22, 18) {
                    message.push_str(&format!(
                        "\n  xx.ts needs node which strips typescript types on its own (22.18+), {} is {}",
                        node::ENV_BINARY,
                        node.version
                    ));
                }
            }
        }
        return Err(message);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    let json = stdout
        .rfind(BEGIN)
        .map(|i| &stdout[i + BEGIN.len()..])
        .and_then(|rest| rest.rfind(END).map(|j| &rest[..j]))
        .ok_or_else(|| format!("loader printed no result for config >{config_str}<"))?;

    model::parse(json, &config_str)
}
