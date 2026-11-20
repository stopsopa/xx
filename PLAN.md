# xx in Rust — implementation plan

Rewrite of `pages/bash/xx` (currently `xx.sh` + `xx.node.cjs` bundled with inquirer) as a Rust binary driven by a thin shell wrapper.

## 1. Decisions in short

| Question | Decision |
| --- | --- |
| Config language | **Stay with JavaScript, same `xx.cjs` contract.** Existing files keep working unchanged. |
| How Rust reads JS | Binary spawns `node` with a tiny embedded loader, which prints the resolved commands as JSON. No bundle, no npm dependencies. |
| Who draws the menu | Rust (`crossterm`), drawn on `/dev/tty`. |
| Who executes the script | **The shell wrapper**, not the binary. You are right: it is the only way `source: true` can affect the current shell. |
| Binary → wrapper protocol | stdout = path of the generated script, exit code = what to do with it (same codes as today: `0`, `55`, `10`, `130`). |
| `--lock` / `--unlock` / `--copy` | Stay in the old bash script, untouched. Not part of the first version. |
| Repo layout, tests, CI, releases | Same as `stopsopa/securenv` (section 8), with the few differences xx needs. |

## 2. Why JS stays as the config language

Requirements: inject env vars, complete freedom in generating the final script, backward compatibility with a lot of existing `xx.cjs` files.

| Option | Freedom | Existing files work | Runtime dependency | Verdict |
| --- | --- | --- | --- | --- |
| `xx.cjs` evaluated by `node` subprocess | full Node (fs, child_process, `require`, `process.env`) | yes, 100% | node | **chosen** |
| JS engine embedded in the binary (QuickJS via `rquickjs`) | JS language only; `require`, `fs`, `process` must be re-implemented by us | only files that use no Node API | none | later, optional (section 10, question 5) |
| TOML / YAML + templating | low; multi-line bash in YAML/TOML plus a template language is worse than template literals | no, needs migration | none | rejected |
| Lua / Rhai / Starlark embedded | good, but a new language to write | no | none | rejected |

Reasoning:

- A static format cannot do what `xx.cjs` does today (shared snippets like `enter` / `esc`, colour constants, computed keys, spreading other objects). Any static format ends up needing a template language, which is a worse JS.
- Node is already required by the tool today, so nothing gets worse.
- Cost measured on this machine: real `node -e ''` takes about 30 ms; the current bundled inquirer script takes about 60 ms. Through the asdf shim, node startup is about 110 ms, so the shim is the biggest cost, not JS. Section 5 has a way around it.
- The loader sits behind a trait, so an embedded engine or `xx.toml` can be added later without touching the rest.

### What Rust buys when node is still required

Node is not embedded in the binary; the binary starts the `node` already installed on the machine. With that design the gain from Rust is small:

| | Today (node + inquirer bundle) | Rust + node subprocess | Rust + embedded QuickJS |
| --- | --- | --- | --- |
| Start to menu, real node | about 60 ms | about 35 ms | about 5 ms |
| Start to menu, through asdf shim | about 140 ms | about 115 ms | about 5 ms |
| Needs node installed | yes | yes | no |
| Bundle step, npm dependencies | yes (647 KB bundle, inquirer) | no | no |
| Menu highlight under our control | no (inquirer theme) | yes | yes |
| Configs using `require("fs")` etc. | work | work | do not work |

The first two columns are measured or derived from measurements on this machine; the QuickJS figure is an estimate, not measured.

What Rust + node gives: no bundle and no inquirer, about 25 ms faster, and a menu that cannot break on a dependency upgrade. All three can also be had by rewriting `xx.node.cjs` as a dependency-free node script with its own raw-mode menu (about 200 lines), without Rust, CI matrix or release binaries.

So Rust is only clearly worth it with the embedded engine: no node needed (containers, fresh machines), and the asdf shim cost disappears. The template and securenv's `xx.cjs` use only plain JS, so they would run in QuickJS as they are. This makes question 5 in section 10 the main decision of the whole plan.

### Config contract (unchanged)

```js
module.exports = (setup) => ({
  "command name": {
    command: `...bash...`, // required, string
    description: "...",    // optional, defaults to the key
    confirm: false,        // optional, default TRUE (asks "Run command?")
    source: true,          // optional, default false (run in current shell)
    order: 10,             // optional, integer
  },
});
```

Additions that do not break existing files:

- The function may be `async` / return a Promise.
- The function receives a context instead of `{}`: `{ args, cwd, configPath, gitDir, env }`. Old files ignore it, and `...setup` at the end of the template must keep working, so the context is passed as a **second** argument: `module.exports = (setup, ctx) => ...`, with `setup` staying `{}`.
- `command` may be a function `(ctx) => string`, evaluated only for the selected command. That allows expensive generation (calling git, reading files) without slowing down the menu. This needs a second node run after selection; see section 5.
- `xx.mjs` and `xx.ts` are accepted in the same lookup places (node 24 runs both natively). `.cjs` wins if several exist.

## 3. Architecture

```
alias xx='source ".../xx.sh"'          (unchanged for the user)
        │
        ▼
xx.sh  (sourced, bash + zsh)
  ├─ --lock / --unlock / --copy  → existing bash code, as is
  └─ everything else:
        OUT="$(xx-bin "$@")"   ; CODE=$?
            │
            ▼
        xx-bin (Rust)
          1. find config + decide generated-script path
          2. node loader → JSON list of commands
          3. pick command: menu on /dev/tty, or by name / number
          4. confirm if needed
          5. write generated script
          6. print its path on stdout, exit with code
        │
        ▼
  CODE 0   → /bin/bash "$OUT" "$@"
  CODE 55  → source "$OUT" "$@" ; set +e
  CODE 10  → generated, not confirmed: print info
  CODE 130 → cancelled
  other    → error (binary already printed it on stderr)
```

Why stdout carries the path: the binary, not bash, then owns the config lookup and the generated-file location, and the wrapper shrinks to about 30 lines. The menu is drawn on `/dev/tty`, so capturing stdout with `$(...)` does not interfere.

The wrapper keeps the existing shell detection block (`_DIR` for bash and zsh) and looks for the binary in this order:

1. `${XX_BIN}` if set,
2. `${_DIR}/bin/<arch>/xx` (repo checkout after `compile.sh`, same place securenv uses),
3. `${_DIR}/xx-bin` (installed from a release, next to `xx.sh`).

The installed binary is called `xx-bin`, not `xx`, so it never competes with the `xx` alias.

`--lock`, `--unlock` and `--copy` need `gitstorage.cjs` from the `stopsopa.github.io` repo, so they cannot move here cleanly. The new wrapper forwards those three flags to the old script at `${XX_LEGACY_SH}` and prints a clear error when that variable is not set.

## 4. Behaviour to preserve (taken from the current code)

Lookup and output paths:

| Config found | Generated script |
| --- | --- |
| `./.git/xx.cjs` | `./.git/xx_generated.sh` |
| `./xx.cjs`, `./.git` is a directory | `./.git/xx_generated.sh` |
| `./xx.cjs`, no `./.git` directory | `~/xx_generated.sh` |
| `~/xx.cjs` | `~/xx_generated.sh` |

Other rules:

- `<% name %>` in `command` and `description` is replaced with the key.
- `xx` with no arguments opens the menu; `xx <name|number> [args...]` runs directly. A number is tried before a name. Remaining args become `$1 $2 ...` of the generated script.
- `confirm` is `true` when missing. `XXCONFIRM=false` in env skips every confirmation.
- The script is written even when the user answers "no" (exit 10), and the old generated file is deleted at start.
- `source: true` → exit 55 → wrapper sources the file, then `set +e`.
- Ctrl+C → exit 130, cursor restored.
- Node is started with `NODE_OPTIONS=""` (your environment has an inspector in `NODE_OPTIONS`; without clearing it every run prints "Debugger listening").
- Menu look: prompt `Select command to run`, rows `█   1 - name` (number right-aligned to 3, the leading block is the position indicator from `lib/range.js`), **selected row in reverse video (`\e[7m`)**, description of the selected row under the list, help line `↑↓ navigate • ⏎ select`, and after choosing a single line `✔ Select command to run <row>`.

Things I found that look like bugs; the plan fixes them unless you say otherwise:

1. `xx --gen` does not work today: `--gen` is passed to node as the command name and fails with "function >--gen< not defined". New: `xx --gen [name] [args]` generates, prints the script and does not run it.
2. `xx 3` picks the third entry in **file order**, while the menu numbers are shown **after sorting by `order`**. New: the number always means the number shown in the menu.
3. The `order` comparator is inconsistent (returns `1` whenever either side has no `order`), so the result depends on the JS engine's sort. New rule: stable sort, missing `order` counts as `0`. So `order: 1001` goes to the end and `order: -1` to the top, and files without any `order` keep file order.
4. `[ -d ./.git ]` fails in git worktrees and submodules, where `.git` is a file. New: the binary resolves the real git dir.

## 5. The node loader

Embedded in the binary with `include_str!`, run as `node -e <loader> <configPath> <ctxJson>`:

1. `require(configPath)` (or `import()` for `.mjs` / `.ts`), check the export is a function.
2. Call it, await the result, check it is a plain object.
3. Print `Object.entries(result)` as a JSON **array** on a dedicated file descriptor (fd 3), so `console.log` inside a config cannot corrupt the output. An array, because JSON object key order is not something to rely on across parsers, and JS itself moves integer-like keys (`"1"`, `"2"`) to the front; the array keeps exactly what node saw.
4. For `command` given as a function, emit `{ "lazy": true }`; after selection the binary runs the loader again with `--resolve <key>`.

Validation errors (`command` is not a string, export is not a function) are reported by Rust with the config path and key, exit code 1.

Finding node: `XX_NODE` env var if set, otherwise `node` from `PATH`. Setting `XX_NODE` to the real binary (`asdf which node`) skips the asdf shim and saves about 80 ms per run. The binary does not cache the evaluated config, because a config may depend on env and on files.

## 6. Rust crate layout

securenv is one `src/main.rs`. xx has three separate concerns (config loading, terminal UI, file generation), so it gets a few flat files, no nested modules:

```
src/
  main.rs        arg parsing, exit codes, top-level flow, --help / --version / --init / --list / --gen
  locate.rs      config lookup, git dir resolution, generated-script path
  loader.rs      node subprocess, JSON parsing, validation
  loader.js      embedded with include_str!
  model.rs       Command { name, command, description, confirm, source, order }, <% name %>, sorting
  menu.rs        select + confirm, key handling, drawing, terminal guard (restores on drop and on panic)
  range.rs       port of lib/range.js (block characters + easeOutExpo mirror)
xx-template.cjs  embedded with include_str! for --init
```

Dependencies: `crossterm` (raw mode, keys, colours), `serde` + `serde_json`, `unicode-width` (emoji in names and descriptions). Argument parsing by hand rather than `clap` (which securenv uses), because everything after the command name must pass through to the script untouched. No `ratatui` / `dialoguer` / `inquire`: the menu is about 200 lines and owning it gives exact control over the reverse-video row, which the README says keeps breaking with inquirer upgrades.

Key input goes through one small trait with two implementations: the real terminal, and a scripted one fed from `XX_TEST_KEYS="down,down,enter"`. That makes the menu testable from plain bash without a pty (section 8).

### Menu behaviour

- Keys: `↑` `↓` / `k` `j`, `Home` `End`, `PgUp` `PgDn`, `Enter`, `Esc` / `Ctrl+C` (cancel, 130).
- Typing digits jumps to that number; typing letters filters by substring (new, cheap, and useful with 30+ commands). `Backspace` edits the filter.
- Window of rows sized to terminal height (inquirer shows 7), wraps around at the ends.
- Redraw in place with cursor movement, no alternate screen, so the scrollback stays intact and the final `✔` line remains.
- If stdin/tty is not interactive and no command was named: print the list and exit 1 instead of hanging.

## 7. CLI surface

```
xx                      menu
xx <name|number> [...]  run directly, args passed to the script
xx --gen [name] [...]   generate and print, do not run
xx --list [--json]      print commands (new; useful for shell completion)
xx --init               write template to .git/xx.cjs (error if it exists)
xx --help | --version
xx --lock | --unlock | --copy   handled by xx.sh, as today
```

## 8. Repository, testing and release (following securenv)

Everything below is copied from `stopsopa/securenv` with names changed, except where a difference is called out.

### Files

```
.github/workflows/rust.yml   CI + release
.agents/ , AGENTS.md         copied from securenv (bash-scripting skill applies to every .sh here)
.gitignore                   /target/  /bin/  /__links/
Cargo.toml , Cargo.lock      [profile.release] opt-level = 3, strip = true
build.rs                     version: XX_VERSION env → exact git tag → "dev"; exposed as XX_BUILD_VERSION
bash/detect_arch.sh          sets ARCH_DIR, TARGET, XX_BIN="${ROOT}/bin/${ARCH_DIR}/xx"
bash/file/fuzzy.ts           picker used by tag.sh
compile.sh                   cargo build --release --target ${TARGET} → bin/<arch>/xx
test.sh                      runs every test/test*/test.sh, prints PASS/FAIL and totals
tag.sh                       patch | minor | major → create and push tag
validateenv.sh               rustc, cargo, rustfmt, clippy, cargo fetch; plus a node check
README.md  DEV.md  changelog.md  PLAN.md
src/                         section 6
xx.sh                        the wrapper users source
xx-template.cjs
xx.cjs                       this repo's own menu: help, validateenv, compile, test, publish
test/
  .gitignore                 ignores generated scripts
  test001/
    xx.cjs                   fixture config
    test.sh
    EXPLANATION.md           one or two sentences: what the test proves
```

`--help` and `--version` print the build version and `https://github.com/stopsopa/xx`, as securenv does.

### Tests

Same shape as securenv: each `test/testNNN/test.sh` runs the compiled binary from `bin/<arch>/xx`, checks exit code and output with `grep`, prints the command it ran, exits non-zero with `"${0} error: ..."` on failure.

Differences from securenv:

- **`test.sh` runs `cargo test` first.** securenv has no Rust unit tests; xx has pure functions worth testing that way (`range`, sorting, `<% name %>`, path lookup table from section 4).
- **Each test runs in its own temp directory** (`mktemp -d`, with `HOME` pointed at it too), because the result depends on `pwd`, on `.git` being there or not, and on `~/xx.cjs`.
- **Menu tests use `XX_TEST_KEYS`** instead of a pty, so they stay plain bash and behave the same on macOS and the Linux CI runner.
- **Wrapper tests** run `xx.sh` under both `/bin/bash` and `zsh` (`bash -c 'source xx.sh name'`), since `source: true` is the reason the wrapper exists.

Planned tests:

| Test | Proves |
| --- | --- |
| 001 | `--list` prints commands from `./xx.cjs`, in file order |
| 002 | lookup order: `.git/xx.cjs` wins over `./xx.cjs`, which wins over `~/xx.cjs`; error lists all three when none exists |
| 003 | generated-script path for each row of the table in section 4 |
| 004 | run by name writes the exact `command` text, stdout is the path, exit 0 |
| 005 | run by number uses the menu (sorted) number; number is tried before name |
| 006 | `source: true` → exit 55; through `xx.sh` a variable exported by the script is visible afterwards (bash and zsh) |
| 007 | `confirm` missing → asks; answer "no" → exit 10 and file still written; `XXCONFIRM=false` skips |
| 008 | `<% name %>` replaced in `command` and `description`; description defaults to the key |
| 009 | `order`: stable sort, missing = 0, negative first |
| 010 | args after the name reach the script as `$1 $2`, including an arg with spaces; script's exit code (54) comes back through `xx.sh` |
| 011 | menu via `XX_TEST_KEYS`: down, down, enter picks the third row; wraps at the ends; digit jump; filter by typing |
| 012 | menu output contains `\e[7m` around the selected row only, and the final `✔` line |
| 013 | cancel (Esc / Ctrl+C) → exit 130, no script written, cursor-show sequence emitted |
| 014 | bad configs: export not a function, `command` not a string, syntax error → exit 1 with config path and key in the message |
| 015 | `console.log` inside the config does not break loading |
| 016 | `--gen name` writes and prints the script without running it; `--init` writes the template and refuses to overwrite |
| 017 | `NODE_OPTIONS=--inspect` in env produces no "Debugger listening" output |
| 018 | worktree: `.git` as a file resolves to the real git dir |

### CI (`.github/workflows/rust.yml`)

Same three jobs and triggers as securenv (every branch, every tag, PRs; `[no ci]` in the commit message skips):

1. **test** on `ubuntu-latest`: `compile.sh`, then `test.sh`. Extra steps for xx: `actions/setup-node` (the loader needs node) and `apt-get install zsh` (wrapper tests).
2. **build-matrix** (needs test), same targets and naming:

   | Target | Runner | Asset |
   | --- | --- | --- |
   | `aarch64-apple-darwin` | `macos-latest` | `xx-darwin-arm64` |
   | `x86_64-unknown-linux-gnu` | `ubuntu-latest` | `xx-linux-x64` |
   | `aarch64-unknown-linux-gnu` | `ubuntu-latest` + `cross` | `xx-linux-arm64` |

   `XX_VERSION` is set from `github.ref_name`.
3. **release** (tags only): collect artifacts, write `SHA256SUMS.txt`, generate release notes, publish with `softprops/action-gh-release`.

### Release page

Same structure as securenv releases: change notes on top, then "Installation & Checksum Verification" with a `curl` / `wget` / checksum block per binary, then the checksum table.

Differences:

- **`xx.sh` is a release asset too**, and is included in `SHA256SUMS.txt`. The binary alone is not usable.
- **The install block installs two files and prints the alias**:

  ```bash
  mkdir -p ~/.xx
  curl -fL -o ~/.xx/xx-bin https://github.com/stopsopa/xx/releases/download/<tag>/xx-darwin-arm64
  curl -fL -o ~/.xx/xx.sh  https://github.com/stopsopa/xx/releases/download/<tag>/xx.sh
  chmod a+x ~/.xx/xx-bin
  echo '<hash>  xx-bin' | (cd ~/.xx && shasum -a 256 -c -)
  # add to ~/.bashrc or ~/.zshrc:
  alias xx='source "${HOME}/.xx/xx.sh"'
  ```

- **Change notes come from `changelog.md` automatically.** In securenv the workflow generates only the install part, and the notes on top of each release look pasted in by hand. Proposal: give `changelog.md` one `## vX.Y.Z` heading per release, and have the release job put the section matching the tag above the install block. `tag.sh` refuses to tag when `changelog.md` has no section for the new version.

### Releasing

Same as securenv: `/bin/bash tag.sh patch|minor|major` (or `xx publish`), CI does the rest. `DEV.md` describes local setup, build, tests and this flow.

## 9. Milestones

1. **Repo skeleton**: copy the securenv scaffolding (section 8 file list), `validateenv.sh`, `compile.sh`, empty `test.sh`, CI running on push. Green pipeline with a binary that only prints `--version`.
2. **Loading**: `locate.rs`, node loader, `--list`. Tests 001–003, 014, 015, 017.
3. **Direct run**: `xx <name> [args]`, generation, exit codes, new `xx.sh` wrapper. Tests 004–010.
4. **Menu**: select + confirm, reverse-video row, range indicator, description line, cancel and terminal restore. Tests 011–013.
5. **Parity pass**: `--gen`, `--init`, worktree git dir, non-interactive behaviour. Tests 016, 018. Then use it daily next to the old one (`alias xxn=...`) before switching the `xx` alias.
6. **First release**: release job with `xx.sh` asset and changelog extraction, README, DEV.md, `v1.0.0`.
7. **Later**: lazy `command` functions, `xx.mjs` / `xx.ts`, shell completion from `--list`, port of the `--lock` family, optional embedded engine.

## 10. Open questions for you

1. **No `.git` directory**: today the script goes to `~/xx_generated.sh`, shared by every terminal, so two `xx` runs at once can overwrite each other. Proposal: `${TMPDIR}/xx-<uid>/<hash of cwd>.sh`. Keep `~/xx_generated.sh` or switch?
2. **Lookup only in `pwd`**: should `xx` walk up to the repo root so it works from subdirectories? Proposal: yes, walk up to the first directory with `xx.cjs` or `.git`, and `cd` is **not** changed; the script still runs in the directory you are in. This changes which config is picked in nested setups, so it is your call.
3. **Merging `~/xx.cjs`**: today it is used only when no local config exists. Your screenshot shows a `~/help` entry, which suggests you copy global entries by hand. Should the global file be merged into every menu (local wins on name clash)?
4. **Bug fixes 2 and 3 in section 4** change numbering and ordering in edge cases. OK to change, or keep the old behaviour exactly?
5. **Embedded JS engine (the main decision, see "What Rust buys" in section 2)**: three ways to go:
   - **A.** Rust + embedded QuickJS as the default engine, node used only when a config asks for it (for example a `// xx:node` comment on the first line, or `XX_ENGINE=node`). Node-free and fastest for plain-JS configs; costs a small host API to write (`process.env`, `process.argv`, `process.cwd()`, `console`, `require` of relative `.cjs` / `.json` files).
   - **B.** Rust + node subprocess only, as the rest of this plan describes. Simplest Rust version, smallest gain.
   - **C.** No Rust: rewrite `xx.node.cjs` without dependencies. Least work, keeps the node requirement.

   My recommendation is A if you want the Rust project, C if the goal is only to get rid of the bundle and the inquirer highlight problem. Do any of your real `xx.cjs` files use `require` or Node APIs?
6. **`--lock` family**: forwarding to the old script through `XX_LEGACY_SH` keeps it working but means two installs. Alternative is to copy `gitstorage.cjs` logic here later. Is forwarding fine for now?
7. **Changelog per version**: OK to switch `changelog.md` to `## vX.Y.Z` headings so release notes are filled in by CI?
8. **Intel Mac and musl builds**: securenv ships neither. Add `x86_64-apple-darwin` or `*-linux-musl` (Alpine containers), or keep the same three targets?
