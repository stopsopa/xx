use serde_json::Value;

/**
 * One entry of xx.cjs:
 *
 *   "name": { command, description, confirm, source, order }
 */
#[derive(Debug, Clone, PartialEq)]
pub struct Command {
    pub name: String,
    pub command: String,
    pub description: String,
    // None = not specified in config, which means: ask
    pub confirm: Option<bool>,
    pub source: bool,
    pub order: Option<i64>,
}

/**
 * Replaces <% name %> (any amount of whitespace inside) with given name.
 */
pub fn replace_name(text: &str, name: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("<%") {
        let after = &rest[start + 2..];
        let inner = after.trim_start();
        let matched = inner
            .strip_prefix("name")
            .map(|t| t.trim_start())
            .and_then(|t| t.strip_prefix("%>"));
        match matched {
            Some(tail) => {
                out.push_str(&rest[..start]);
                out.push_str(name);
                rest = tail;
            }
            None => {
                out.push_str(&rest[..start + 2]);
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

// JS truthiness, used for "source" flag like the old implementation did (if (command.source))
fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().map(|f| f != 0.0).unwrap_or(false),
        Value::String(s) => !s.is_empty(),
        _ => true,
    }
}

/**
 * Turns json printed by loader.js ([[key, {..}], ...]) into validated list of commands.
 * Result is sorted the way it is presented in the menu.
 */
pub fn parse(json: &str, config: &str) -> Result<Vec<Command>, String> {
    let root: Value = serde_json::from_str(json)
        .map_err(|e| format!("can't parse loader output for >{config}<: {e}"))?;

    let entries = root
        .as_array()
        .ok_or_else(|| format!("loader output for >{config}< is not an array"))?;

    let mut list = Vec::with_capacity(entries.len());

    for entry in entries {
        let name = entry
            .get(0)
            .and_then(Value::as_str)
            .ok_or_else(|| format!("malformed entry in loader output for >{config}<"))?;
        let value = entry.get(1).unwrap_or(&Value::Null);

        let command = value
            .get("command")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                format!("value.command for key >{name}< in >{config}< is not a string")
            })?;

        let description = match value.get("description").and_then(Value::as_str) {
            Some(d) => d,
            None => name,
        };

        list.push(Command {
            name: name.to_string(),
            command: replace_name(command, name),
            description: replace_name(description, name),
            confirm: value.get("confirm").and_then(Value::as_bool),
            source: value.get("source").map(truthy).unwrap_or(false),
            order: value.get("order").and_then(Value::as_i64),
        });
    }

    sort(&mut list);

    Ok(list)
}

/**
 * Stable sort by "order". Missing order counts as 0, so:
 *   negative order -> top, positive order -> bottom, no order at all -> order from the file
 */
pub fn sort(list: &mut [Command]) {
    list.sort_by_key(|c| c.order.unwrap_or(0));
}

/**
 * xx <number> picks by number shown in the menu, xx <name> by key.
 * Number is tried first.
 */
pub fn pick<'a>(list: &'a [Command], what: &str) -> Option<&'a Command> {
    if !what.is_empty() && what.bytes().all(|b| b.is_ascii_digit()) {
        if let Ok(n) = what.parse::<usize>() {
            if n >= 1 && n <= list.len() {
                return Some(&list[n - 1]);
            }
        }
    }
    list.iter().find(|c| c.name == what)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replace_name_variants() {
        assert_eq!(replace_name("a <%name%> b", "X"), "a X b");
        assert_eq!(replace_name("a <%  name  %> b <% name %>", "X"), "a X b X");
        assert_eq!(replace_name("a <% other %> b", "X"), "a <% other %> b");
        assert_eq!(replace_name("<% <%name%>", "X"), "<% X");
        assert_eq!(replace_name("no tags", "X"), "no tags");
    }

    #[test]
    fn parse_defaults() {
        let list = parse(r#"[["a",{"command":"echo <% name %>"}]]"#, "f").unwrap();
        assert_eq!(list[0].command, "echo a");
        assert_eq!(list[0].description, "a");
        assert_eq!(list[0].confirm, None);
        assert!(!list[0].source);
    }

    #[test]
    fn parse_command_not_string() {
        let err = parse(r#"[["a",{"command":5}]]"#, "f").unwrap_err();
        assert!(err.contains(">a<"), "{err}");
    }

    #[test]
    fn sort_is_stable_and_missing_order_is_zero() {
        let json = r#"[
            ["a",{"command":""}],
            ["b",{"command":"","order":1001}],
            ["c",{"command":""}],
            ["d",{"command":"","order":-1}],
            ["e",{"command":""}]
        ]"#;
        let names: Vec<String> = parse(json, "f")
            .unwrap()
            .into_iter()
            .map(|c| c.name)
            .collect();
        assert_eq!(names, ["d", "a", "c", "e", "b"]);
    }

    #[test]
    fn pick_number_before_name() {
        let json = r#"[["2",{"command":"two"}],["x",{"command":"second"}]]"#;
        let list = parse(json, "f").unwrap();
        assert_eq!(pick(&list, "2").unwrap().command, "second");
        assert_eq!(pick(&list, "x").unwrap().command, "second");
        assert_eq!(pick(&list, "1").unwrap().command, "two");
        assert!(pick(&list, "9").is_none());
    }
}
