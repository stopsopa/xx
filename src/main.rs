/*!
 * xx - menu of shell commands defined in xx.ts (or xx.js, xx.mjs, xx.cjs)
 *
 * This binary never executes the selected command itself. It only:
 *   1. finds the config
 *   2. lets the user pick a command (menu, name or number)
 *   3. writes script of the command to a file
 *   4. prints path of that file to stdout and tells through exit code what to do with it
 *
 * The file is then executed by xx.sh (sourced through alias), because only the shell itself
 * can "source" a script into current shell (source: true).
 *
 * Exit codes (contract with xx.sh):
 *     0 - run generated script with /bin/bash
 *    55 - source generated script in current shell
 *    10 - script generated, but user answered "no" to "Run command?"
 *   130 - cancelled (Esc, Ctrl+C)
 *     1 - error
 *
 * Handshake (the other part of the contract), xx.sh does it before every use of the binary:
 *
 *   xx --handshake      prints: xx-handshake:1:<version of the binary>
 *
 * xx.sh refuses to continue if the answer has different shape (XX_BIN points to something else)
 * or if the version is different than version of xx.sh itself.
 */
mod loader;
mod locate;
mod menu;
mod model;
mod node;
mod range;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{exit, Command as Process, Stdio};

const VERSION: &str = env!("XX_BUILD_VERSION");
const HOMEPAGE: &str = "https://github.com/stopsopa/xx";

// source of truth for --init: json with urls of templates, one for each flavour of the config
const INIT_CONFIG: &str = "https://raw.githubusercontent.com/stopsopa/xx/main/init.json";
const ENV_INIT_CONFIG: &str = "XX_INIT_CONFIG";

const HANDSHAKE_PROTOCOL: &str = "1";

const EXIT_RUN: i32 = 0;
const EXIT_SOURCE: i32 = 55;
const EXIT_NOT_CONFIRMED: i32 = 10;
const EXIT_CANCELLED: i32 = 130;
const EXIT_ERROR: i32 = 1;

fn fail(message: &str) -> ! {
    eprintln!("xx error: {message}");
    exit(EXIT_ERROR);
}

fn help() {
    println!(
        "xx {VERSION}
{HOMEPAGE}

Menu of shell commands defined in xx.ts (or xx.js, xx.mjs, xx.cjs)

Usage:
  xx                         open the menu
  xx <name|number> [args]    run command directly, args are passed to its script (${{1}}, ${{2}} ...)
                             number is the one shown in the menu
  xx -- [args]               open the menu and pass args to the script of selected command
  echo data | xx <name>      stdin is passed to the script

  xx --gen [name|number]     generate the script and print it, don't run
  xx --list [--json]         print defined commands
  xx --init [ts|js|mjs|cjs]  download template of the config (default: ts)
                             to .git/xx.<ext>, or to ./xx.<ext> if there is no .git
  xx --esm [path]            download template xx.ts (typescript, es module) to given path
                             (file or directory), default the same place as --init
  xx --help
  xx --version

Config lookup, first found wins:
  .git/xx.ts  .git/xx.js  .git/xx.mjs  .git/xx.cjs
  ./xx.ts     ./xx.js     ./xx.mjs     ./xx.cjs
  ~/xx.ts     ~/xx.js     ~/xx.mjs     ~/xx.cjs

Module format:
  xx.mjs  always es module:  export default (setup, ctx) => ({{ ... }})
  xx.cjs  always commonjs:   module.exports = (setup, ctx) => ({{ ... }})
  xx.js   es module or commonjs, node decides: \"type\" in the nearest package.json,
          without \"type\" by syntax used in the file
  xx.ts   like xx.js, types are stripped by node itself (node 22.18+)

Config format:
  export default (setup, ctx) => ({{
    \"command name\": {{
      command: `echo shell script here`,
      description: \"shown under the menu\",   // optional
      confirm: false,                        // optional, default true: ask before running
      source: true,                          // optional, default false: run in current shell
      order: 10,                             // optional, lower goes first, missing = 0
    }},
  }});

Environment variables:
  XX_NODE_BINARY      required: absolute path to node binary, checked on every run
  XX_NODE_OPTIONS     when defined, NODE_OPTIONS of node started by xx is set to this value
                      (not defined: NODE_OPTIONS is passed as it is)
  XX_BIN              required by xx.sh: absolute path to this binary
  XX_INIT_CONFIG      used by --init and --esm: url or path of json with locations of templates
                      {{\"ts\": \"url or path\", \"js\": \"...\", \"mjs\": \"...\", \"cjs\": \"...\"}}
                      default: {INIT_CONFIG}
  XX_CONFIRM=false    skip all \"Run command?\" questions
  XX_TMP              directory for generated scripts when there is no .git:
                      ${{XX_TMP}}/xx-<uid>/<hash of pwd>.sh
                      (not defined: ${{TMPDIR}} of the system, then /tmp)

Details: {HOMEPAGE}#environment-variables"
    );
}

fn cwd() -> PathBuf {
    std::env::current_dir()
        .unwrap_or_else(|e| fail(&format!("can't determine current directory: {e}")))
}

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .filter(|h| !h.is_empty())
        .map(PathBuf::from)
}

// <XX_TMP>/xx-<uid>/<hash of cwd>.sh
fn fallback_generated(cwd: &Path) -> PathBuf {
    // XX_TMP, then TMPDIR which the system provides (macOS: private directory of the user), then /tmp
    let tmp = ["XX_TMP", "TMPDIR"]
        .iter()
        .filter_map(std::env::var_os)
        .find(|t| !t.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    // SAFETY: getuid has no preconditions and can't fail
    let uid = unsafe { libc::getuid() };
    locate::tmp_generated(&tmp, uid, cwd)
}

fn locate_or_fail(cwd: &Path) -> locate::Located {
    match locate::locate(cwd, home().as_deref(), &fallback_generated(cwd)) {
        Ok(located) => located,
        Err(checked) => {
            let list: Vec<String> = checked
                .iter()
                .map(|p| format!("  {}", p.display()))
                .collect();
            let names: Vec<String> = locate::EXTENSIONS
                .iter()
                .map(|e| format!("xx.{e}"))
                .collect();
            fail(&format!(
                "config not found, looked for {} in:\n{}\n\n  to create one run: xx --init",
                names.join(", "),
                list.join("\n")
            ));
        }
    }
}

fn load_or_fail(
    node: &node::Node,
    located: &locate::Located,
    cwd: &Path,
    args: &[String],
) -> Vec<model::Command> {
    let list = loader::load(node, &located.config, cwd, args).unwrap_or_else(|e| fail(&e));
    if list.is_empty() {
        fail(&format!(
            "no commands defined in >{}<",
            located.config.display()
        ));
    }
    list
}

/**
 * Writes the script. Directory of the script outside of .git (<tmp>/xx-<uid>) is created here,
 * private for the user: in shared /tmp nobody else can be allowed to prepare it for us
 * and swap the script we are about to execute.
 */
fn write_generated(path: &Path, content: &str) -> Result<(), String> {
    use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};

    if let Some(dir) = path.parent() {
        if !dir.exists() {
            fs::DirBuilder::new()
                .mode(0o700)
                .create(dir)
                .map_err(|e| format!("can't create directory >{}<: {e}", dir.display()))?;
        }

        let is_private_tmp = dir
            .file_name()
            .map(|n| n.to_string_lossy().starts_with("xx-"))
            .unwrap_or(false);

        if is_private_tmp {
            let meta = fs::symlink_metadata(dir)
                .map_err(|e| format!("can't check directory >{}<: {e}", dir.display()))?;
            // SAFETY: getuid has no preconditions and can't fail
            let uid = unsafe { libc::getuid() };
            if !meta.is_dir() || meta.uid() != uid {
                return Err(format!(
                    "directory >{}< is not a directory owned by current user, refusing to write a script there",
                    dir.display()
                ));
            }
            if meta.permissions().mode() & 0o022 != 0 {
                return Err(format!(
                    "directory >{}< is writable by other users, refusing to write a script there",
                    dir.display()
                ));
            }
        }
    }

    fs::write(path, content).map_err(|e| format!("can't write >{}<: {e}", path.display()))
}

/**
 * xx --list [--json]
 */
fn list(node: &node::Node, json: bool) {
    let cwd = cwd();
    let located = locate_or_fail(&cwd);
    let list = load_or_fail(node, &located, &cwd, &[]);

    if json {
        let items: Vec<serde_json::Value> = list
            .iter()
            .enumerate()
            .map(|(i, c)| {
                serde_json::json!({
                    "number": i + 1,
                    "name": c.name,
                    "description": c.description,
                    "confirm": c.confirm,
                    "source": c.source,
                    "order": c.order,
                })
            })
            .collect();
        println!("{}", serde_json::Value::Array(items));
        return;
    }

    for (i, c) in list.iter().enumerate() {
        if c.description == c.name {
            println!("{:>3} - {}", i + 1, c.name);
        } else {
            println!("{:>3} - {}\t{}", i + 1, c.name, c.description);
        }
    }
}

fn is_url(source: &str) -> bool {
    source.starts_with("http://") || source.starts_with("https://")
}

/**
 * Content of given url (curl, wget when curl is not installed) or of local file.
 * Relative path of local file is resolved against base.
 */
fn fetch(source: &str, base: &Path) -> Result<Vec<u8>, String> {
    let content = if is_url(source) {
        let run = |program: &str, args: &[&str]| {
            Process::new(program)
                .args(args)
                .arg(source)
                .stdin(Stdio::null())
                .stderr(Stdio::inherit())
                .output()
                .ok()
        };

        let output = run("curl", &["-fsSL"])
            .or_else(|| run("wget", &["-q", "-O", "-"]))
            .ok_or_else(|| format!("neither curl nor wget found, can't download >{source}<"))?;

        if !output.status.success() {
            return Err(format!("downloading >{source}< failed"));
        }

        output.stdout
    } else {
        let path = Path::new(source.strip_prefix("file://").unwrap_or(source));
        let path = if path.is_absolute() {
            path.to_path_buf()
        } else {
            base.join(path)
        };
        fs::read(&path).map_err(|e| format!("can't read file >{}<: {e}", path.display()))?
    };

    if content.is_empty() {
        return Err(format!(">{source}< is empty"));
    }

    Ok(content)
}

/**
 * xx --init [ts|js|mjs|cjs]
 * xx --esm [path]            (kind is always ts, target is given)
 *
 * Templates are never embedded in the binary, two steps are done:
 *
 * - json is taken from XX_INIT_CONFIG (default: init.json published on github, the source
 *   of truth), shape: `{"ts": "...", "js": "...", "mjs": "...", "cjs": "..."}`
 * - template is taken from location found under the key of requested kind
 *
 * In both steps location is url (http, https) or path of local file.
 */
fn init(kind: &str, target: Option<&str>) {
    let cwd = cwd();

    if !locate::EXTENSIONS.contains(&kind) {
        fail(&format!(
            "unknown kind of the config >{kind}<, allowed: {}",
            locate::EXTENSIONS.join(", ")
        ));
    }

    let target = match target {
        Some(t) => {
            let path = cwd.join(t);
            if path.is_dir() {
                path.join(format!("xx.{kind}"))
            } else {
                path
            }
        }
        None => locate::init_target(&cwd, kind),
    };

    if target.exists() {
        fail(&format!("file >{}< already exist", target.display()));
    }

    let config_source = match std::env::var(ENV_INIT_CONFIG) {
        Ok(u) if !u.trim().is_empty() => u.trim().to_string(),
        _ => INIT_CONFIG.to_string(),
    };

    let config_bytes = fetch(&config_source, &cwd)
        .unwrap_or_else(|e| fail(&format!("{ENV_INIT_CONFIG}=>{config_source}<: {e}")));

    let config: serde_json::Value = serde_json::from_slice(&config_bytes).unwrap_or_else(|e| {
        fail(&format!(
            "{ENV_INIT_CONFIG}=>{config_source}<: it is not valid json: {e}"
        ))
    });

    let template_source = match config.get(kind).and_then(serde_json::Value::as_str) {
        Some(s) if !s.trim().is_empty() => s.trim().to_string(),
        _ => fail(&format!(
            "{ENV_INIT_CONFIG}=>{config_source}<: key >{kind}< is missing or it is not a string, expected json:\n  {{\"ts\": \"url or path\", \"js\": \"url or path\", \"mjs\": \"url or path\", \"cjs\": \"url or path\"}}"
        )),
    };

    // relative path of a template in local json is relative to that json
    let base = if is_url(&config_source) {
        cwd.clone()
    } else {
        let path = cwd.join(
            config_source
                .strip_prefix("file://")
                .unwrap_or(&config_source),
        );
        path.parent().map(Path::to_path_buf).unwrap_or(cwd.clone())
    };

    let template = fetch(&template_source, &base).unwrap_or_else(|e| {
        fail(&format!(
            "template >{kind}< from {ENV_INIT_CONFIG}=>{config_source}<: {e}"
        ))
    });

    if let Err(e) = fs::write(&target, template) {
        fail(&format!("can't create >{}<: {e}", target.display()));
    }

    println!(
        "    file:\n        {}\n    generated from:\n        {template_source}\n    listed in:\n        {config_source}",
        target.display()
    );
}

/**
 * Main flow: pick command, write its script.
 *
 *   what      - Some(name or number) when given in command line, None = menu
 *   args      - arguments for the final script (only passed to config as context here,
 *               xx.sh is the one passing them to the script)
 *   gen_only  - xx --gen: write and print the script, no confirmation, nothing will be executed
 */
fn run(node: &node::Node, what: Option<&str>, args: &[String], gen_only: bool) -> ! {
    let cwd = cwd();
    let located = locate_or_fail(&cwd);

    // stale script from previous run must never be executed by mistake
    if located.generated.exists() {
        let _ = fs::remove_file(&located.generated);
    }

    let list = load_or_fail(node, &located, &cwd, args);

    let mut term: Option<Box<dyn menu::Term>> = None;

    let command = match what {
        Some(what) => match model::pick(&list, what) {
            Some(c) => c,
            None => fail(&format!(
                "function >{what}< not defined in >{}<",
                located.config.display()
            )),
        },
        None => {
            let t = term.insert(menu::open_term().unwrap_or_else(|e| {
                fail(&format!(
                    "{e}\n  menu needs a terminal, without it name the command: xx <name|number>\n  list of commands: xx --list"
                ))
            }));
            match menu::select(t.as_mut(), &list) {
                Some(i) => &list[i],
                None => {
                    drop(term);
                    exit(EXIT_CANCELLED);
                }
            }
        }
    };

    let write = || {
        if let Err(e) = write_generated(&located.generated, &command.command) {
            fail(&e);
        }
    };

    if gen_only {
        drop(term);
        write();
        println!(
            "xx: script generated >{}<, content:\n{}\n",
            located.generated.display(),
            command.command
        );
        exit(EXIT_RUN);
    }

    // confirm: false -> run straight away, anything else -> ask, unless XX_CONFIRM=false
    let mut confirmed = command.confirm == Some(false);

    if std::env::var("XX_CONFIRM").as_deref() == Ok("false") {
        confirmed = true;
    } else if !confirmed {
        if term.is_none() {
            term = Some(menu::open_term().unwrap_or_else(|e| {
                fail(&format!(
                    "{e}\n  command >{}< needs confirmation and there is no terminal, use XX_CONFIRM=false",
                    command.name
                ))
            }));
        }
        match menu::confirm(term.as_mut().unwrap().as_mut(), &command.name) {
            Some(answer) => confirmed = answer,
            None => {
                drop(term);
                exit(EXIT_CANCELLED);
            }
        }
    }

    // restore the terminal before anything else is printed
    drop(term);

    write();

    println!("{}", located.generated.display());

    if !confirmed {
        exit(EXIT_NOT_CONFIRMED);
    }

    if command.source {
        exit(EXIT_SOURCE);
    }

    exit(EXIT_RUN);
}

// splits "[name|number] [args...]" / "-- [args...]" into what to run and arguments of the script
fn split(args: &[String]) -> (Option<&str>, &[String]) {
    match args.first().map(String::as_str) {
        None => (None, args),
        Some("--") => (None, &args[1..]),
        Some(name) => (Some(name), &args[1..]),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    // these work without node
    match args.first().map(String::as_str) {
        Some("--help") | Some("-h") => return help(),
        Some("--version") | Some("-V") => return println!("xx {VERSION}"),
        Some("--handshake") => return println!("xx-handshake:{HANDSHAKE_PROTOCOL}:{VERSION}"),
        _ => {}
    }

    // everything else: node is checked first, on every run
    let node = node::resolve().unwrap_or_else(|e| fail(&e));

    match args.first().map(String::as_str) {
        Some("--list") => list(&node, args.get(1).map(String::as_str) == Some("--json")),
        Some("--init") => init(args.get(1).map(String::as_str).unwrap_or("ts"), None),
        Some("--esm") => init("ts", args.get(1).map(String::as_str)),
        Some("--gen") => {
            let (what, rest) = split(&args[1..]);
            run(&node, what, rest, true);
        }
        _ => {
            let (what, rest) = split(&args);
            run(&node, what, rest, false);
        }
    }
}
