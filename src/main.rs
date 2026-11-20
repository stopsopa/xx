/**
 * xx - menu of shell commands defined in xx.cjs
 *
 * This binary never executes the selected command itself. It only:
 *   1. finds xx.cjs
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
 */
mod loader;
mod locate;
mod menu;
mod model;
mod range;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{exit, Command as Process, Stdio};

const VERSION: &str = env!("XX_BUILD_VERSION");
const HOMEPAGE: &str = "https://github.com/stopsopa/xx";

// source of truth for --init
const TEMPLATE_URL: &str = "https://raw.githubusercontent.com/stopsopa/xx/main/xx-template.cjs";

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

Menu of shell commands defined in xx.cjs

Usage:
  xx                         open the menu
  xx <name|number> [args]    run command directly, args are passed to its script (${{1}}, ${{2}} ...)
  xx -- [args]               open the menu and pass args to the script of selected command
  echo data | xx <name>      stdin is passed to the script

  xx --gen [name|number]     generate the script and print it, don't run
  xx --list [--json]         print defined commands
  xx --init                  download fresh template from github to .git/xx.cjs (./xx.cjs if no .git)
  xx --help
  xx --version

Handled by xx.sh (old implementation, needs XX_LEGACY_SH):
  xx --lock | --unlock | --copy

Config lookup (first found wins):
  .git/xx.cjs
  ./xx.cjs
  ~/xx.cjs

Config format:
  module.exports = (setup) => ({{
    \"command name\": {{
      command: `echo shell script here`,
      description: \"shown under the menu\",   // optional
      confirm: false,                        // optional, default true: ask before running
      source: true,                          // optional, default false: run in current shell
      order: 10,                             // optional, lower goes first, missing = 0
    }},
  }});

Environment variables:
  XXCONFIRM=false     skip all \"Run command?\" questions
  XX_NODE             path to node binary used to load the config (default: node from PATH)
  XX_BIN              used by xx.sh: path to this binary
  XX_TEMPLATE_URL     used by --init: where to download the template from
                      default: {TEMPLATE_URL}"
    );
}

fn cwd() -> PathBuf {
    std::env::current_dir().unwrap_or_else(|e| fail(&format!("can't determine current directory: {e}")))
}

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").filter(|h| !h.is_empty()).map(PathBuf::from)
}

fn locate_or_fail(cwd: &Path) -> locate::Located {
    match locate::locate(cwd, home().as_deref()) {
        Ok(located) => located,
        Err(checked) => {
            let list: Vec<String> = checked.iter().map(|p| format!("  {}", p.display())).collect();
            fail(&format!(
                "xx.cjs doesn't exist in any location normally searched:\n{}\n\n  to create one run: xx --init",
                list.join("\n")
            ));
        }
    }
}

fn load_or_fail(located: &locate::Located, cwd: &Path, args: &[String]) -> Vec<model::Command> {
    let list = loader::load(&located.config, cwd, args).unwrap_or_else(|e| fail(&e));
    if list.is_empty() {
        fail(&format!("no commands defined in >{}<", located.config.display()));
    }
    list
}

/**
 * xx --list [--json]
 */
fn list(json: bool) {
    let cwd = cwd();
    let located = locate_or_fail(&cwd);
    let list = load_or_fail(&located, &cwd, &[]);

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

/**
 * xx --init
 *
 * Template is always downloaded from github (never embedded in the binary),
 * so file published in the repository is the only source of truth.
 */
fn init() {
    let target = locate::init_target(&cwd());

    if target.exists() {
        fail(&format!("file >{}< already exist", target.display()));
    }

    let url = match std::env::var("XX_TEMPLATE_URL") {
        Ok(u) if !u.trim().is_empty() => u,
        _ => TEMPLATE_URL.to_string(),
    };

    let tmp = PathBuf::from(format!("{}.download", target.display()));
    let _ = fs::remove_file(&tmp);

    let run = |program: &str, args: &[&str]| -> Option<bool> {
        Process::new(program)
            .args(args)
            .stdin(Stdio::null())
            .status()
            .ok()
            .map(|s| s.success())
    };

    let tmp_str = tmp.to_string_lossy().to_string();

    // curl first, wget when curl is not installed
    let downloaded = match run("curl", &["-fsSL", "-o", &tmp_str, &url]) {
        Some(ok) => ok,
        None => match run("wget", &["-q", "-O", &tmp_str, &url]) {
            Some(ok) => ok,
            None => fail("neither curl nor wget found, can't download the template"),
        },
    };

    let size = fs::metadata(&tmp).map(|m| m.len()).unwrap_or(0);

    if !downloaded || size == 0 {
        let _ = fs::remove_file(&tmp);
        fail(&format!("downloading template from >{url}< failed"));
    }

    if let Err(e) = fs::rename(&tmp, &target) {
        let _ = fs::remove_file(&tmp);
        fail(&format!("can't create >{}<: {e}", target.display()));
    }

    println!("    file:\n        {}\n    generated from:\n        {url}", target.display());
}

/**
 * Main flow: pick command, write its script.
 *
 *   what      - Some(name or number) when given in command line, None = menu
 *   args      - arguments for the final script (only passed to config as context here,
 *               xx.sh is the one passing them to the script)
 *   gen_only  - xx --gen: write and print the script, no confirmation, nothing will be executed
 */
fn run(what: Option<&str>, args: &[String], gen_only: bool) -> ! {
    let cwd = cwd();
    let located = locate_or_fail(&cwd);

    // stale script from previous run must never be executed by mistake
    if located.generated.exists() {
        let _ = fs::remove_file(&located.generated);
    }

    let list = load_or_fail(&located, &cwd, args);

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
        if let Err(e) = fs::write(&located.generated, &command.command) {
            fail(&format!("can't write >{}<: {e}", located.generated.display()));
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

    // confirm: false -> run straight away, anything else -> ask, unless XXCONFIRM=false
    let mut confirmed = command.confirm == Some(false);

    if std::env::var("XXCONFIRM").as_deref() == Ok("false") {
        confirmed = true;
    } else if !confirmed {
        if term.is_none() {
            term = Some(menu::open_term().unwrap_or_else(|e| {
                fail(&format!(
                    "{e}\n  command >{}< needs confirmation and there is no terminal, use XXCONFIRM=false",
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

    match args.first().map(String::as_str) {
        Some("--help") | Some("-h") => help(),
        Some("--version") | Some("-V") => println!("xx {VERSION}"),
        Some("--list") => list(args.get(1).map(String::as_str) == Some("--json")),
        Some("--init") => init(),
        Some("--gen") => {
            let (what, rest) = split(&args[1..]);
            run(what, rest, true);
        }
        _ => {
            let (what, rest) = split(&args);
            run(what, rest, false);
        }
    }
}
