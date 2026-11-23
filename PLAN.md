# xx — design

Rewrite of `stopsopa.github.io/pages/bash/xx` (`xx.sh` + `xx.node.cjs` bundled with inquirer) as a Rust binary driven by a thin shell wrapper.

This file started as the implementation plan. It now describes **what was built and why**. How to use the tool is in `README.md`, how to work on the repository in `DEV.md`.

## 1. Decisions in short

| Question                         | Decision                                                                                                                                                                  |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Config language                  | JavaScript / TypeScript, the same contract the old `xx.cjs` had. Old files work unchanged.                                                                                |
| How Rust reads the config        | The binary starts the installed `node` (`XX_NODE_BINARY`) with a small loader compiled into the binary. The loader prints the commands as JSON. Node is **not** embedded. |
| Who draws the menu               | The binary, on `/dev/tty`, raw mode through `libc`. No terminal library.                                                                                                  |
| Who executes the script          | **The shell wrapper `xx.sh`**, never the binary. It is the only way `source: true` can change the current shell.                                                          |
| Binary → wrapper protocol        | stdout = path of the generated script, exit code = what to do with it.                                                                                                    |
| Wrapper → binary trust           | `xx.sh` accepts only a binary whose md5 was embedded into it by the build.                                                                                                |
| Repo layout, tests, CI, releases | Modelled on `stopsopa/securenv`, with the differences xx needs (section 9).                                                                                               |

## 2. Why JS, and why node is still needed

Requirements were: inject env vars, complete freedom in generating the final script, existing `xx.cjs` files keep working.

| Option                                     | Verdict                                                                                                                                             |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Config evaluated by a `node` subprocess    | **chosen**: full Node (`fs`, `child_process`, imports, `process.env`), 100% backward compatible                                                     |
| JS engine embedded in the binary (QuickJS) | rejected for now: no node needed and faster, but `require`, `fs`, `process` would have to be re-implemented and configs using Node APIs would break |
| TOML / YAML + templating                   | rejected: cannot do shared snippets, computed keys, spreading; ends up as a worse JS                                                                |
| Lua / Rhai / Starlark                      | rejected: new language, no backward compatibility                                                                                                   |

Honest cost of this choice: with node still required, Rust buys little speed (one node start per run, roughly 30–50 ms, stays). What it does buy: no bundle, no npm dependencies at runtime, and a menu fully under our control (the inquirer highlight kept breaking on upgrades).

## 3. Architecture

```
alias xx='source ~/.xx/xx.sh'
        │
        ▼
xx.sh  (sourced, bash 3.2+ and zsh)
  1. __xx_check_bin: XX_BIN defined, exists, executable, md5 on the embedded list
  2. --help --version --list --init --esm --gen --env --update: run the binary, return its code
     (--update: path of xx.sh itself is passed in __XX_SH_PATH, the binary can't know it)
     (--env with broken XX_BIN: raw values of XX_* env vars are printed after the error)
  3. everything else:
        GENERATED="$("${XX_BIN}" "$@" < /dev/null)" ; CODE=$?
            │
            ▼
        xx binary (Rust)
          a. check XX_NODE_BINARY (every run except --help / --version)
          b. find the config, decide where the generated script goes
          c. node loader → list of commands (sorted by order)
          d. pick: by name / number from arguments, otherwise menu on /dev/tty
          e. "Run command?" if needed
          f. write the script, print its path on stdout, exit with code
        │
        ▼
  0   → /bin/bash "${GENERATED}" args
  55  → __xx_source "${GENERATED}" args      (source: true)
  10  → written, but the user answered "no": print info, return 10
  130 → cancelled (Esc, Ctrl+C)
  other → error, already printed by the binary on stderr
```

Why stdout carries the path: the binary owns config lookup and the location of the generated file, the wrapper only executes. The menu is drawn on `/dev/tty` (or stderr in tests), so capturing stdout with `$(...)` does not interfere.

**Arguments.** `xx <name|number> a b` and `xx -- a b` (menu): the wrapper drops the first word and passes the rest to the script as `${1} ${2}`. The binary gets them too, only to hand them to the config as `ctx.args`.

**Stdin.** The binary and node are started with `< /dev/null`, the menu and the confirmation read keys from `/dev/tty`. So stdin of `xx` is still untouched when the wrapper runs the script: `echo data | xx name` and `xx name < file` reach the script, also when the command was picked from the menu.

**`~/` in paths.** `XX_BIN`, `XX_NODE_BINARY`, `XX_INIT_CONFIG` (and paths inside its json), `XX_TMP` and `XX_RELEASES` may start with `~/`. The shell does not expand `~` inside quotes, so the wrapper and the binary (`locate::expand_tilde`) do it themselves.

## 4. Contract between `xx.sh` and the binary

Two files that must never be mixed between builds, so the wrapper verifies the binary on every call:

- `xx.sh` in the repository contains two literal lines: `__XX_VERSION="dev"` and `__XX_BIN_MD5=""`. With the empty list it refuses to work.
- `bash/embed.sh <version> <output> <binary>...` copies it, replacing those two lines with the version and the md5 of the given binaries. `compile.sh` produces `bin/<arch>/xx.sh` for the one binary it built. The release job produces **one** `xx.sh` carrying the md5 of all three platform binaries; that is why it is a list.
- On every call the wrapper computes the md5 of `XX_BIN` (`md5sum`, or `md5` on macOS) and continues only if it is on the list. Another program, another version, a rebuilt, modified or half-downloaded binary are all refused.
- The error shows both hashes plus the version of `xx.sh` and what the file answers to `--version`, because a mismatch usually means "different versions".

`XX_BIN` is required; nothing is searched next to `xx.sh` or anywhere else.

**`--update` (`src/update.rs`)** has to replace both files in one go, because of the contract above:

- Nothing is scraped from the release page. `<releases>/latest` redirects to `.../tag/<tag>` (published releases only, no API rate limit), files are at `<releases>/download/<tag>/<file>`. `XX_RELEASES` may point to a local directory with the same layout (`latest` is then a file with the tag); the tests use that.
- The platform is not detected at runtime: the running binary knows its compile target, that picks `xx-darwin-arm64`, `xx-linux-x64` or `xx-linux-arm64`.
- The binary can't know where `xx.sh` is, the wrapper passes its own path in `__XX_SH_PATH` (`BASH_SOURCE`, in zsh `%x`).
- Order: download next to the installed files (`<file>.new-<pid>`, same filesystem, so rename is atomic) → sha256 from `SHA256SUMS.txt` → test of the new pair → copies of the installed files (`<file>.old-<pid>`) → two renames → the same test with the installed files, on failure both old files are put back.
- The test of the pair is `source xx.sh --version` in a real shell (`/bin/bash`, plus zsh when it is `$SHELL`) with `XX_BIN` set to the binary: the wrapper has to load, accept the md5 and the binary has to run here, both printing the expected tag.
- No restart of the shell is needed because the alias sources `xx.sh` on every call. The call which runs the update keeps using functions already loaded in memory.
- Not possible on purpose: updating an installation where the md5 check already fails (the wrapper would have to run a file it doesn't recognise), and updating a `dev` build.

## 5. Config: lookup, formats, loading

Lookup, first found wins. In every directory the order is `xx.ts`, `xx.js`, `xx.mjs`, `xx.cjs`:

| Config in                             | Generated script                      |
| ------------------------------------- | ------------------------------------- |
| `.git/`                               | `.git/xx_generated.sh`                |
| `./` and `.git` exists                | `.git/xx_generated.sh`                |
| `./` without `.git`                   | `${XX_TMP}/xx-<uid>/<hash of pwd>.sh` |
| `~/` (only when nothing above exists) | `${XX_TMP}/xx-<uid>/<hash of pwd>.sh` |

- Only the current directory is checked, no walking up. `~/xx.*` is a fallback, it is not merged into project menus (undecided, see section 10).
- `.git` being a file (worktree, submodule: `gitdir: path`) is resolved to the real git directory.
- The temp path replaced `~/xx_generated.sh`, which was shared by all terminals. `XX_TMP` falls back to `TMPDIR`, then `/tmp`. The hash is FNV-1a of `pwd` (stable between versions). The `xx-<uid>` directory is created `700` and refused if it is not owned by the user or is writable by others: in a shared `/tmp` nobody else may be able to swap a script that is about to be executed.
- A stale generated script is deleted at the start of every run, so a cancelled run can never execute the previous one.

Module format is decided by node, xx adds no rules: `.mjs` always ESM, `.cjs` always CommonJS, `.js` and `.ts` by `"type"` in the nearest `package.json`, and by syntax when there is no `"type"`. `xx.ts` is executed by node itself (type stripping, 22.18+).

The loader (`src/loader.js`, compiled in with `include_str!`, run as `node -e <loader> <config> <ctx json>`):

1. `import()` the config. It works for every flavour; for CommonJS `module.exports` arrives as `default`.
2. Call the exported function as `fn({}, ctx)` with `ctx = { args, cwd, configPath }` and await it (it may be async). The first argument stays `{}` so `...setup` at the end of old configs keeps working.
3. Print `Object.entries(result)` as a JSON **array** between two markers. An array, because it keeps exactly the order node saw; object key order is not safe across parsers and JS itself moves integer-like keys to the front.
4. `process.stdout.write` is redirected to stderr first, so `console.log` in a config cannot corrupt the JSON. Rust takes the text between the last pair of markers.
5. One node warning is silenced (`MODULE_TYPELESS_PACKAGE_JSON`): it would print four lines on every run for an ESM `xx.js` / `xx.ts` in a project whose `package.json` has no `"type"`.

Node itself (`src/node.rs`): `XX_NODE_BINARY` is required, no fallback to `PATH` (version-manager shims are slow and depend on the directory). Every run checks that the file exists and that `--version` prints `vX.Y.Z`. `XX_NODE_OPTIONS`, when not empty, replaces `NODE_OPTIONS` for node started by xx; not defined or empty means `NODE_OPTIONS` passes through untouched (empty = default, like in every other `XX_*` variable; a single space is the way to force empty `NODE_OPTIONS`).

Rules applied in Rust (`src/model.rs`):

- `command` must be a string. `description` defaults to the key. `<% name %>` in both is replaced with the key.
- `confirm` missing means ask. `XX_CONFIRM=false` skips every question. `source` uses JS truthiness.
- `order`: stable sort, missing counts as 0, so negative goes to the top, positive to the bottom, and configs without `order` keep file order. The old comparator was inconsistent.
- `xx <number>` means the number **shown in the menu** (after sorting); a number is tried before a name. The old tool used the position in the file.

## 6. Menu

- Prompt `Select command to run`, rows `█   1 - name` (block indicator ported from `lib/range.js`), **selected row in reverse video**, description of the selected row under the list, help line, and after choosing a single `✔` line. Redrawn in place, no alternate screen, so scrollback stays intact.
- Keys: `↑` `↓` (wrap around), `Home` `End` `PgUp` `PgDn`, `Enter`. Typing filters rows: case-insensitive "contains" against `<number> - <name>`, so `12` finds row 12 too. `Backspace` edits the filter, `Esc` or `Ctrl+C` cancels (130) at any moment, also with a filter typed in. `j` / `k` do not navigate, because typing filters.
- "Run command?": `Enter` / `y` = yes, `n` / `Esc` = no (exit 10, the script is still written), `Ctrl+C` = cancel (130).
- Without a terminal the menu and the confirmation fail with an explanation instead of hanging (name the command, or `XX_CONFIRM=false`).
- Key input goes through one trait with two implementations: the real `/dev/tty`, and a scripted one driven by `XX_TEST_KEYS="down,down,enter"` (`XX_TEST_SIZE="60x20"`), which draws to stderr. That makes the menu testable from plain bash.

## 7. `source: true` and Ctrl+C — the hardest part

The problem: a sourced script containing `set -e` runs inside the user's interactive shell. Ctrl+C kills the command the script was waiting for, that counts as a failed command, and `set -e` then closes the whole shell, which is the terminal. Any failing command does the same even without Ctrl+C.

Consequence accepted: **in `source: true` scripts `set -e` is neutralised** (the script continues after a failed command). Ctrl+C stops the script and returns to the prompt with code 130. `exit` inside such a script still closes the terminal; nothing can be done about that from outside.

Each shell needed a different trick (`__xx_source` in `xx.sh`, all found by experiment, covered by `test/test018`):

- **zsh**: `setopt localoptions localtraps`, `trap 'return 130' INT`, then `if source file; then …; else code=$?; fi`. zsh ignores `set -e` in anything executed as a condition, and the options are reverted when the function returns. `set +e` must be called before returning a non-zero code, otherwise that `return` itself closes the shell.
- **bash**: the `if source` trick does not suppress errexit in bash 3.2 (macOS), and a trap on `INT` either killed bash 3.2 or hung bash 5. What works is a `DEBUG` trap with `set -T` and `shopt -s extdebug`, run before every command of the script (`__xx_guard`):
  - it calls `set +e`, so whatever the script switched on is off again before the next command runs;
  - when the previous command ended with 130 it remembers the interrupt and returns 2, which with `extdebug` means "skip this command and return from the current function / sourced file", repeated until the script is unwound;
  - bash 5 jumps straight to the prompt on Ctrl+C without passing through the cleanup code, so the guard also cleans up after itself when it notices it is running at a shallower call depth than where it was installed.
  - `__xx_guard_off` restores the trap and the `-T` / `-E` / `extdebug` settings the shell had before.

In bash, `echo data | xx name` with `source: true` cannot change the current shell (each part of a pipe runs in a subshell); `xx name < file` can.

## 8. `--init`, templates, GitHub Pages

- `xx --init [ts|js|mjs|cjs]` (default `ts`) writes `.git/xx.<kind>`, or `./xx.<kind>` without `.git`. `xx --esm [path]` writes the `ts` template to a given file or directory. An existing file is never overwritten.
- Nothing is embedded in the binary. Two steps: fetch a json (`XX_INIT_CONFIG`, default `https://stopsopa.github.io/xx/init.json`) of the form `{"ts": "...", "js": "...", "mjs": "...", "cjs": "..."}`, then fetch the template listed under the requested key. Both the json and the templates can be URLs (`curl`, then `wget`) or local paths; relative paths in a local json are relative to that json. Local paths are what the tests use.
- Only `templates/xx.ts` is written by hand and committed. `transpile.sh` (esbuild, `bash/transpile.mjs`) generates `xx.js`, `xx.mjs`, `xx.cjs`: types removed, `export default` kept or turned into `module.exports =`. esbuild drops comments, so the comment block at the top of `xx.ts` is carried over by the script. Every generated file is then loaded and must return exactly what `xx.ts` returns.
- The generated files are git-ignored and exist only on GitHub Pages: job `pages-build` runs `transpile.sh`, then publishes the repository root (without `.git`, `.github`, `target`, `bin`, `node_modules`, `vendor`, `__links`). That is why `init.json` points to Pages and not to the `main` branch.
- Pages are published by two jobs on purpose: `deploy-pages` in the same job as the upload did not see the artifact yet (actions/deploy-pages#451).

## 9. Repository, tests, release

```
src/main.rs      arguments, exit codes, --help --version --list --init --esm --gen --env, main flow
src/update.rs    --update
src/locate.rs    config lookup, git dir, generated-script path, ~/ expansion
src/node.rs      XX_NODE_BINARY check, XX_NODE_OPTIONS
src/loader.rs    runs node with loader.js, extracts the JSON
src/loader.js    the loader (section 5)
src/model.rs     Command, validation, <% name %>, sorting, pick by number / name
src/menu.rs      select + confirm, real and scripted terminal
src/range.rs     block indicator
build.rs         version: XX_VERSION env, otherwise "dev"
xx.sh            source of the wrapper          bash/embed.sh    version + md5 into xx.sh
compile.sh       → bin/<arch>/xx and xx.sh      transpile.sh     templates/xx.ts → js, mjs, cjs
test.sh          transpile, cargo test, e2e     tag.sh           semver bump, push tag
validateenv.sh   toolchain check                bash/release_notes.sh  body of the release page
templates/xx.ts  init.json  xx.ts (menu of this repository)  package.json (esbuild only)
```

Dependencies: `libc`, `serde_json`, `unicode-width`. Arguments are parsed by hand, because everything after the command name must pass through untouched.

Tests: `cargo test` for pure logic, then 23 end-to-end tests in `test/testNNN/` (each with `EXPLANATION.md`).

- Every test gets its own temp `pwd`, `HOME` and `XX_TMP`, because the result depends on all three; `NODE_OPTIONS` and other `XX_*` variables are unset.
- The wrapper is tested under `/bin/bash` (3.2 on macOS) and `zsh`.
- `test/test018` is the only one with a real pseudo terminal (`terminal.py`): real Ctrl+C and arrow-key escape sequences in system bash, modern bash and zsh, in parallel. It waits for prompts and expected text, never for a fixed time. One trap worth remembering: a background job of a non-interactive bash ignores SIGINT and the children inherit that, so the script resets SIGINT to default before starting the shell under test.
- `test/test017` and `test/test023` cover the md5 contract, `test/test019`–`021` the twelve config locations and the `package.json` `"type"` cases, `test/test022` the node variables.

CI is one workflow (`.github/workflows/rust.yml`), so one push gives one run. Always: **test** on Linux x64 (node 24, zsh, `npm ci`, `compile.sh`, `test.sh`); **build-matrix** for `aarch64-apple-darwin`, `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu` (the last through `cross`), with `XX_VERSION` set to the tag only for tag builds; then only for a tag **release**, and only for `main` (after **test**) **pages-build** → **pages-deploy**. Nothing is published when tests fail.

Release: `/bin/bash tag.sh patch|minor|major` pushes a `vX.Y.Z` tag and CI does the rest. The release job builds the single `xx.sh` with `bash/embed.sh`, writes `SHA256SUMS.txt` for the binaries and `xx.sh`, and generates the page: the `## vX.Y.Z` section of `changelog.md`, then for each platform a block that downloads the binary (as `xx-bin`) and `xx.sh` to the current directory and verifies both checksums. `README.md` → Installation continues from there.

## 10. Not done, undecided

- **Merging `~/xx.*` into project menus**: undecided. Today the home config is used only when the project has none.
- **`--lock` / `--unlock` / `--copy`**: dropped, may come back as a Rust implementation.
- **`command` as a function** (evaluated only for the selected command): not implemented.
- **Embedded JS engine** (no node needed): not done, see section 2.
- **Intel Mac and musl builds**: not wanted, the three targets above are enough.
- **Walking up to the repository root** to find the config: not wanted, lookup stays in the current directory.
- `.agents/` and `AGENTS.md` were not copied from securenv.
