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
 * The other part of the contract is checked by xx.sh alone: md5 of this binary has to be
 * one of the hashes embedded in xx.sh by the build (bash/embed.sh).
 */
mod loader;
mod locate;
mod menu;
mod model;
mod node;
mod range;
mod update;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{exit, Command as Process, Stdio};

const VERSION: &str = env!("XX_BUILD_VERSION");
const HOMEPAGE: &str = "https://github.com/stopsopa/xx";

// source of truth for --init: json with urls of templates, one for each flavour of the config.
// GitHub Pages of the repository: xx.js, xx.mjs and xx.cjs exist only there,
// generated from templates/xx.ts by transpile.sh when Pages are published
const INIT_CONFIG: &str = "https://stopsopa.github.io/xx/init.json";
const ENV_INIT_CONFIG: &str = "XX_INIT_CONFIG";
const RELEASES: &str = update::RELEASES;
const ENV_CONFIG: &str = "XX_CONFIG";

// value of --config given in command line (set once, at the beginning of main)
static CONFIG_ARG: std::sync::OnceLock<Option<String>> = std::sync::OnceLock::new();

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

  xx --config <path> ...     use this config instead of searching for one. Has to be given
                             before the name of the command, works with everything above
                             and with --gen and --list. <path> is a file (any name, extension
                             .ts .js .mjs .cjs) or a directory with xx.ts, xx.js, xx.mjs, xx.cjs.
                             The command is still executed in the current directory.
                             One config with tools, used from any directory:
                               alias ai='xx --config \"/Users/me/project/pages/ai/xx.ts\"'
                               ai linkrepo restore

  xx --gen [name|number]     generate the script and print it, don't run
  xx --list [--json]         print defined commands
  xx --init [ts|js|mjs|cjs]  download template of the config (default: ts)
                             to .git/xx.<ext>, or to ./xx.<ext> if there is no .git
  xx --esm [path]            download template xx.ts (typescript, es module) to given path
                             (file or directory), default the same place as --init
  xx --update [tag|--check]  replace xx.sh and the binary with the latest release (or given one,
                             e.g. v0.1.0). Both files are downloaded, verified and tested
                             together before anything is replaced. --check only reports
  xx --help
  xx --version

Config lookup, first found wins:
  .git/xx.ts  .git/xx.js  .git/xx.mjs  .git/xx.cjs
  ./xx.ts     ./xx.js     ./xx.mjs     ./xx.cjs
  ~/xx.ts     ~/xx.js     ~/xx.mjs     ~/xx.cjs
  --config <path> or XX_CONFIG skips all of it: only that config is used, no fallback

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
      description: \"shown under the menu\",
      confirm: true,
      source: true,
      order: 10,
    }},
  }});

  setup is always {{}} (\"...setup\" at the end of old configs still works),
  ctx is {{ args, cwd, configPath, configDir }}. The function may be async.
    args        arguments given after the name of the command
    cwd         directory xx was called in, the script is executed there
    configPath  absolute path of the config in use
    configDir   directory of the config, to reach files living next to it:
                command: `/bin/bash \"${{ctx.configDir}}/xx/tool.sh\" \"\\${{@}}\"`

Fields of a command, only \"command\" is required:
  command      string   required. Shell script, written to a file and executed with /bin/bash.
                        Arguments of xx are its ${{1}}, ${{2}} ...
  description  string   default: name of the command.
                        Shown under the menu for the selected row
  confirm      boolean  default: false = run straight away.
                        true = ask \"Run command?\" first (Enter or y = yes, n or Esc = no).
                        Only true asks, any other value means false.
                        XX_CONFIRM=false skips the question also for confirm: true
  source       boolean  default: false = executed with /bin/bash as a separate process.
                        true = sourced in the current shell, so cd, export or
                        \"source venv/bin/activate\" still apply after the command ends
  order        number   default: 0. Lower goes first: negative = top, positive = bottom.
                        Commands with the same order stay in the order of the file

  <% name %> in command and description is replaced with the name of the command.
  xx --list --json shows all of the above for every command, as xx understood it

Environment variables:
  XX_NODE_BINARY      required: absolute path to node binary, checked on every run
                      (in all paths below \"~/\" at the beginning means home directory)
  XX_NODE_OPTIONS     when not empty, NODE_OPTIONS of node started by xx is set to this value
                      (not defined or empty: NODE_OPTIONS is passed as it is,
                      a single space \" \" gives node empty NODE_OPTIONS)
  XX_BIN              required by xx.sh: absolute path to this binary, xx.sh accepts only
                      the binary it was built with (md5 of the file is checked)
  XX_INIT_CONFIG      used by --init and --esm: url or path of json with locations of templates
                      {{\"ts\": \"url or path\", \"js\": \"...\", \"mjs\": \"...\", \"cjs\": \"...\"}}
                      default: {INIT_CONFIG}
  XX_CONFIRM=false    skip all \"Run command?\" questions (asked by commands with confirm: true)
  XX_TMP              directory for generated scripts when there is no .git:
                      ${{XX_TMP}}/xx-<uid>/<hash of pwd>.sh
                      (not defined: ${{TMPDIR}} of the system, then /tmp)
  XX_RELEASES         used by --update: url or directory with releases
                      default: {RELEASES}
  XX_CONFIG           the same as --config <path>: file or directory with the config to use
                      instead of searching for one. --config wins when both are given.
                      Exported, it is also seen by xx called from a command of xx

  xx --env            table of all variables above: value, default and final value
                      which xx really uses right now (after defaults and expanding \"~/\")

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
    locate::tmp_generated(&tmp_dir(), uid(), cwd)
}

fn uid() -> u32 {
    // SAFETY: getuid has no preconditions and can't fail
    unsafe { libc::getuid() }
}

fn tmp_dir() -> PathBuf {
    ["XX_TMP", "TMPDIR"]
        .iter()
        .filter_map(|name| std::env::var(name).ok())
        .find(|t| !t.is_empty())
        .map(|t| PathBuf::from(locate::expand_tilde(&t, home().as_deref())))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

// where --init and --esm take the list of templates from: url or path ("~/" already expanded)
fn init_config_source() -> String {
    let source = match std::env::var(ENV_INIT_CONFIG) {
        Ok(u) if !u.trim().is_empty() => u.trim().to_string(),
        _ => INIT_CONFIG.to_string(),
    };
    if is_url(&source) {
        source
    } else {
        locate::expand_tilde(
            source.strip_prefix("file://").unwrap_or(&source),
            home().as_deref(),
        )
    }
}

/**
 * xx --env
 *
 * One row for every env var xx reacts to:
 *   value   - what is in the environment right now
 *   default - what is used when the variable is not defined
 *   final   - what xx really works with, after defaults and expanding "~/"
 */
fn env() {
    let home = home();
    let raw = |name: &str| match std::env::var(name) {
        Ok(v) => format!(">{v}<"),
        Err(_) => "not defined".to_string(),
    };
    let path = |name: &str| match std::env::var(name) {
        Ok(v) if !v.trim().is_empty() => {
            format!(">{}<", locate::expand_tilde(v.trim(), home.as_deref()))
        }
        _ => "missing, it is required".to_string(),
    };

    let node = node::resolve(home.as_deref());

    let rows: Vec<[String; 4]> = vec![
        [
            "name".to_string(),
            "value".to_string(),
            "default".to_string(),
            "final (used by xx right now)".to_string(),
        ],
        [
            node::ENV_BINARY.to_string(),
            raw(node::ENV_BINARY),
            "none, required".to_string(),
            match &node {
                Ok(n) => format!(">{}< (node {})", n.path, n.version),
                Err(_) => format!("{} (not usable, see below)", path(node::ENV_BINARY)),
            },
        ],
        [
            node::ENV_OPTIONS.to_string(),
            raw(node::ENV_OPTIONS),
            "${NODE_OPTIONS}".to_string(),
            // what node started by xx really gets as NODE_OPTIONS, and where it comes from
            match node::options() {
                Some(v) => format!(
                    ">{}< (${{NODE_OPTIONS}} is ignored)",
                    v.to_string_lossy()
                ),
                None => format!("{} (taken from ${{NODE_OPTIONS}})", raw("NODE_OPTIONS")),
            },
        ],
        [
            "XX_BIN".to_string(),
            raw("XX_BIN"),
            "none, required".to_string(),
            path("XX_BIN"),
        ],
        [
            ENV_INIT_CONFIG.to_string(),
            raw(ENV_INIT_CONFIG),
            INIT_CONFIG.to_string(),
            format!(">{}<", init_config_source()),
        ],
        [
            "XX_CONFIRM".to_string(),
            raw("XX_CONFIRM"),
            "true".to_string(),
            if std::env::var("XX_CONFIRM").as_deref() == Ok("false") {
                "false (never ask \"Run command?\")".to_string()
            } else {
                "true (ask when the command has confirm: true)".to_string()
            },
        ],
        [
            "XX_TMP".to_string(),
            raw("XX_TMP"),
            "${TMPDIR}, then /tmp".to_string(),
            format!(
                ">{}< (scripts in >{}<)",
                tmp_dir().display(),
                tmp_dir().join(format!("xx-{}", uid())).display()
            ),
        ],
        [
            update::ENV_RELEASES.to_string(),
            raw(update::ENV_RELEASES),
            update::RELEASES.to_string(),
            format!(">{}<", update::releases()),
        ],
        [
            ENV_CONFIG.to_string(),
            raw(ENV_CONFIG),
            "none: .git/xx.* ./xx.* ~/xx.*".to_string(),
            match config_request() {
                Some((value, from)) => {
                    let from = if from == ENV_CONFIG {
                        String::new()
                    } else {
                        format!(" (from {from}, it wins)")
                    };
                    match locate::explicit(&value, &cwd(), home.as_deref()) {
                        Ok(config) => format!(">{}<{from}", config.display()),
                        Err(e) => format!("ERROR: {e}{from}"),
                    }
                }
                None => "not used, the config is searched".to_string(),
            },
        ],
    ];

    let mut widths = [0usize; 3];
    for row in &rows {
        for (i, w) in widths.iter_mut().enumerate() {
            *w = (*w).max(row[i].chars().count());
        }
    }
    for row in &rows {
        println!(
            "{:<a$} | {:<b$} | {:<c$} | {}",
            row[0],
            row[1],
            row[2],
            row[3],
            a = widths[0],
            b = widths[1],
            c = widths[2]
        );
    }

    if let Err(e) = node {
        eprintln!("\nxx error: {e}");
        exit(1);
    }
}

/**
 * Config pointed directly: (value, where it comes from). The argument wins over the env var.
 * Empty XX_CONFIG means not defined, like in the rest of XX_* variables.
 */
fn config_request() -> Option<(String, &'static str)> {
    if let Some(Some(value)) = CONFIG_ARG.get() {
        return Some((value.clone(), "--config"));
    }
    std::env::var(ENV_CONFIG)
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
        .map(|v| (v, ENV_CONFIG))
}

/**
 * Removes "--config <path>" / "--config=<path>" from the beginning of arguments and returns
 * the path. It is an option of xx, so it is recognised only before the name of the command:
 * after the name everything belongs to the command, also literal --config.
 * Given more than once: the last one wins.
 */
fn take_config(args: &mut Vec<String>) -> Result<Option<String>, String> {
    let mut found = None;
    loop {
        let value = match args.first().map(String::as_str) {
            Some("--config") => {
                if args.len() < 2 {
                    return Err(
                        "--config needs a path: xx --config <file or directory> [name] [args]"
                            .to_string(),
                    );
                }
                args.remove(0);
                args.remove(0)
            }
            Some(first) if first.starts_with("--config=") => {
                args.remove(0)["--config=".len()..].to_string()
            }
            _ => return Ok(found),
        };
        if value.trim().is_empty() {
            return Err("--config: the path is empty".to_string());
        }
        found = Some(value.trim().to_string());
    }
}

fn locate_or_fail(cwd: &Path) -> locate::Located {
    // pointed directly: nothing else is searched, no fallback
    if let Some((value, from)) = config_request() {
        return match locate::explicit(&value, cwd, home().as_deref()) {
            Ok(config) => locate::Located {
                generated: locate::tmp_generated_explicit(&tmp_dir(), uid(), cwd, &config),
                config,
            },
            Err(e) => fail(&format!("{from}: {e}")),
        };
    }

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
        // no "exists?" check before: two xx starting at the same time (two terminals) would both
        // see no directory and the slower one would fail. Whatever is there is verified below.
        match fs::DirBuilder::new().mode(0o700).create(dir) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(e) => {
                return Err(format!(
                    "can't create directory >{}<: {e}",
                    dir.display()
                ))
            }
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
        let path = locate::expand_tilde(
            source.strip_prefix("file://").unwrap_or(source),
            home().as_deref(),
        );
        let path = Path::new(&path);
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
 * - json is taken from XX_INIT_CONFIG (default: init.json published on GitHub Pages of the
 *   repository, the source of truth), shape: `{"ts": "...", "js": "...", "mjs": "...", "cjs": "..."}`
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

    let config_source = init_config_source();

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
                "function >{what}< not defined in >{}<{}",
                located.config.display(),
                option_hint(what)
            )),
        },
        None => {
            let t = term.insert(menu::open_term().unwrap_or_else(|e| {
                fail(&format!(
                    "{e}\n  menu needs a terminal, without it name the command: xx <name|number>\n  list of commands: xx --list"
                ))
            }));
            // which menu is it: shown only when the config was pointed directly
            let note = config_request().map(|_| format!("config: {}", located.config.display()));
            match menu::select(t.as_mut(), &list, note.as_deref()) {
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

    // confirm: true -> ask, unless XX_CONFIRM=false. Anything else (also missing) -> run straight away
    let mut confirmed = command.confirm != Some(true);

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

const OPTIONS: [&str; 11] = [
    "--help", "--version", "--list", "--gen", "--init", "--esm", "--env", "--update", "--config",
    "-h", "-V",
];

// number of single character edits (insert, delete, replace) between two words
fn distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut row: Vec<usize> = (0..=b.len()).collect();
    for i in 1..=a.len() {
        let mut previous = row[0];
        row[0] = i;
        for j in 1..=b.len() {
            let current = row[j];
            row[j] = (previous + usize::from(a[i - 1] != b[j - 1]))
                .min(row[j] + 1)
                .min(row[j - 1] + 1);
            previous = current;
        }
    }
    row[b.len()]
}

/**
 * Name of a command which was not found and starts with "-" is most likely a mistyped option
 * of xx (xx --verion). A command can have such a name, so it is only a hint added to the error.
 */
fn option_hint(what: &str) -> String {
    if !what.starts_with('-') {
        return String::new();
    }
    let closest = OPTIONS
        .iter()
        .filter(|o| o.len() > 2)
        .map(|o| (distance(what, o), *o))
        .filter(|(d, _)| *d <= 2)
        .min();
    match closest {
        Some((_, option)) => format!(
            "\n  it looks like an option of xx, did you mean: xx {option}\n  all options: xx --help"
        ),
        None => "\n  it looks like an option of xx, there is no such option, see: xx --help".to_string(),
    }
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
    let mut args: Vec<String> = std::env::args().skip(1).collect();

    let config_arg = take_config(&mut args).unwrap_or_else(|e| fail(&e));
    let _ = CONFIG_ARG.set(config_arg);

    // these work without node
    match args.first().map(String::as_str) {
        Some("--help") | Some("-h") => return help(),
        Some("--version") | Some("-V") => return println!("xx {VERSION}"),
        // only as the only argument, otherwise it is a name of a command like any other
        Some("--env") if args.len() == 1 => return env(),
        Some("--update") => {
            return update::update(&args[1..]).unwrap_or_else(|e| fail(&e));
        }
        _ => {}
    }

    // everything else: node is checked first, on every run
    let node = node::resolve(home().as_deref()).unwrap_or_else(|e| fail(&e));

    match args.first().map(String::as_str) {
        Some("--list") => list(&node, args.get(1).map(String::as_str) == Some("--json")),
        Some(flag @ ("--init" | "--esm")) if CONFIG_ARG.get().is_some_and(Option::is_some) => {
            fail(&format!(
                "--config can't be used together with {flag}: --config points to a config which is used, {flag} creates one.\n  To create the template at given path: xx --esm <file or directory>"
            ))
        }
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
