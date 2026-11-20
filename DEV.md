# Developer Guide

How to make the repository work just after `git clone`.

```sh
git clone git@github.com:stopsopa/xx.git
cd xx
```

## Local Toolchain Setup

### Install Rust

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Add the macOS arm64 target

```sh
rustup target add aarch64-apple-darwin
```

(on other machines `bash/detect_arch.sh` picks the target, see the `TARGET` variable there)

### Other tools

- **node 22.18+** - the `xx` binary runs `node` to load the config, so it is needed to use `xx` and to run the tests. Tests load `xx.ts`, that is where the minimal version comes from (node strips types on its own since 22.18). Also `tag.sh` uses it for the patch / minor / major picker (`bash/file/fuzzy.ts`).
- **zsh** - tests run the wrapper in bash and in zsh.
- **python3** - only `test/test018` (creates a pseudo terminal to press real Ctrl+C).
- **curl** or **wget** - `xx --init` downloads the template with it (tests don't, they use local files).

### Verify toolchain

Run the validation script to confirm everything is in order:

```sh
/bin/bash validateenv.sh
```

Exit 0 means the local toolchain is ready for development.

## Build locally

```sh
/bin/bash compile.sh
```

The binary lands in `bin/<arch>/xx` (`bin/arm64/xx` or `bin/x64/xx`), version inside is `dev`, the same as in `xx.sh` of the repository (they have to match, see "Versions" below).

On stdout `compile.sh` prints only absolute paths of all binaries found in `bin/` after the build, one per line. Everything else goes to stderr:

```sh
/bin/bash compile.sh 2> /dev/null
# /path/to/clone/bin/arm64/xx
```

## Use the local build

Nothing is searched automatically, three lines are needed:

```sh
# ~/.bashrc or ~/.zshrc
export XX_BIN="/path/to/clone/bin/arm64/xx"
export XX_NODE_BINARY="/path/to/node"       # node -e 'console.log(process.execPath)'
alias xx='source "/path/to/clone/xx.sh"'
```

To try it next to the old `xx` without replacing it, give the alias another name (`alias xxn=...`).

This repository has its own `xx.cjs`, so inside of the clone `xx` shows: `help`, `validateenv`, `compile`, `test`, `release notes preview`, `publish`.

## Running Tests Locally

```sh
/bin/bash compile.sh
/bin/bash test.sh
```

`test.sh` runs:

1. `cargo test` - unit tests of pure logic (sorting, `<% name %>`, lookup of the config, menu rows, shape of node version).
2. every `test/test*/test.sh` - end to end tests of the compiled binary and of `xx.sh`. Each directory has `EXPLANATION.md` saying what the test proves.

One test alone:

```sh
/bin/bash test/test006/test.sh
```

Things worth knowing when writing a test:

- Start with the two lines every test starts with (`DIR=...` and `source "${DIR}/../_lib.sh"`). `test/_lib.sh` gives the test an empty temporary directory as `pwd`, another one as `HOME` and another as `XX_TMP`, because result of `xx` depends on `pwd`, on `.git`, on `~/xx.*` and scripts without `.git` go to `XX_TMP`. It also sets `XX_BIN` and `XX_NODE_BINARY` (resolved from `node` in `PATH` unless you set it yourself) and unsets `NODE_OPTIONS` and the rest of `XX_*`.
- `write_config` and `check_config` from `test/_lib.sh` create a config of given flavour (`ts`, `esm`, `cjs`) and check that it is listed, generated and executed (see `test/test019`).
- `xx --init` in tests never touches the network: `XX_INIT_CONFIG` points to a local json with local paths (see `test/test016`).
- The menu is driven without a terminal: `XX_TEST_KEYS="down,down,enter"` (list of keys in `src/menu.rs`, struct `Scripted`). What would be drawn goes to stderr. `XX_TEST_SIZE="60x20"` sets size of the "terminal".
- Real terminal behaviour (Ctrl+C, escape sequences of arrow keys) is tested only in `test/test018` through `terminal.py`. It waits for prompts and expected text, never for a fixed time; keep it that way, fixed sleeps made this test take 15 seconds.

## Layout

```
src/main.rs        arguments, exit codes, --help --version --list --init --esm --gen --handshake, main flow
src/locate.rs      where is the config, where to write the generated script
src/node.rs        XX_NODE_BINARY check, XX_NODE_OPTIONS
src/loader.rs      runs node with loader.js, reads list of commands
src/loader.js      executed by node: imports the config, prints commands as json
src/model.rs       Command, validation, <% name %>, sorting, pick by name / number
src/menu.rs        menu and "Run command?" question, real terminal and scripted one
src/range.rs       block indicator in front of menu rows
build.rs           version: XX_VERSION env, otherwise "dev"
xx.sh              wrapper sourced by the alias, executes the generated script
init.json          default XX_INIT_CONFIG: where xx --init finds templates (github is the source of truth)
templates/         xx.ts xx.js xx.mjs xx.cjs downloaded by xx --init
xx.cjs             xx menu of this repository
bash/              detect_arch.sh, release_notes.sh, file/fuzzy.ts
test/              end to end tests
```

## Contract between `xx.sh` and the binary

Described at the top of `src/main.rs` and `xx.sh`, covered by `test/test017`:

- **Handshake**: before every use `xx.sh` runs `"${XX_BIN}" --handshake` and expects `xx-handshake:1:<version>`. Anything else means `XX_BIN` is not the xx binary.
- **Versions**: `<version>` has to be equal to `__XX_VERSION` in `xx.sh`. In the repository both are `dev`: `xx.sh` has the literal line `__XX_VERSION="dev"` and `build.rs` falls back to `dev`. The release workflow puts the tag into both: `XX_VERSION` env for the build and `sed` over that exact line of `xx.sh`. Don't reformat the line, the workflow (and `test/test017`) fail when it is not found.
- **Exit codes** of the binary tell `xx.sh` what to do with the generated script: `0` run with `/bin/bash`, `55` source, `10` not confirmed, `130` cancelled, anything else is an error.

---

## Release and Publishing Process

### CI/CD Workflow Overview

GitHub Actions pipeline `.github/workflows/rust.yml` handles automated building, testing, and release creation:
- **Pushing code to any branch** (or opening a PR) triggers the CI test suite (`compile.sh` and `test.sh`) on Linux x64 (`ubuntu-latest`) and builds cross-platform binaries to ensure build stability. It does **not** create any release.
- **Pushing a git tag** triggers the CI test suite, compiles all binaries, and publishes a new **GitHub Release**.
- Commit with `[no ci]` in the message doesn't trigger the pipeline.

### Target Platforms Built in CI/CD
- **macOS arm64** (`aarch64-apple-darwin` → `xx-darwin-arm64`)
- **Linux x64** (`x86_64-unknown-linux-gnu` → `xx-linux-x64`)
- **Linux arm64** (`aarch64-unknown-linux-gnu` → `xx-linux-arm64`)

Every release also contains `xx.sh` with the tag embedded as its version (the binary alone is not usable, and the two refuse to work together when their versions differ) and `SHA256SUMS.txt` covering the binaries and `xx.sh`.

---

## Creating a Release

1. Add section `## vX.Y.Z` for the new version to `changelog.md` and commit it. The release workflow copies that section to the top of the release page. Without the section the release page has only the installation part.

2. Preview the release page if you like (prints markdown):

   ```sh
   /bin/bash bash/release_notes.sh v1.0.0 stopsopa/xx <directory with SHA256SUMS.txt>
   # or simply, from the xx menu of this repository:
   xx "release notes preview" v1.0.0
   ```

3. Use the helper script `tag.sh` to bump version and push tag. A release is created only this way, by a pushed tag:

   ```sh
   /bin/bash tag.sh patch   # or minor, major
   ```

   It takes the highest existing `vX.Y.Z` tag and increments it according to semver: `patch` x.y.Z+1, `minor` x.Y+1.0, `major` X+1.0.0. Without any tag it starts from `0.0.0`, so the very first release is `v0.0.1` (patch), `v0.1.0` (minor) or `v1.0.0` (major).

   Before asking for confirmation it warns when: there are uncommitted changes (they will not be in the release), current commit is not pushed, `changelog.md` has no section for the new tag. If pushing the tag fails the local tag is removed, so the next run doesn't skip a version.

Example session:
```text
Fetching git tags...

Previous tag: v0.0.4
Mode:         patch
New tag:      v0.0.5

Press Enter to create and push tag 'v0.0.5', or Ctrl+C to abort...
Enumerating objects: 9, done.
...
To github.com:stopsopa/xx.git
 * [new tag]         v0.0.5 -> v0.0.5
Successfully created and pushed tag >v0.0.5<
```

### What happens next

1. GitHub Actions detects the tag push and runs the pipeline.
2. It compiles binaries for macOS arm64, Linux x64, and Linux arm64. The tag is embedded as the version (`xx --version`).
3. Adds `xx.sh` with the tag embedded, computes SHA-256 hashes for all files and generates the release notes with `bash/release_notes.sh`: section from `changelog.md`, then `curl`, `wget`, and verification commands for each platform (always for two files: the binary and `xx.sh`, downloaded to the current directory). `README.md` → Installation → step 2 continues from there.
4. Creates and publishes the GitHub Release with attached platform binaries, `xx.sh` and `SHA256SUMS.txt`.

After the first release check that `README.md` → Installation still matches what the release page says.

---

## GitHub Pages

`.github/workflows/pages.yml` publishes the root directory of the repository to https://stopsopa.github.io/xx/ on every push to `main` (and on demand: Actions → GitHub Pages → Run workflow). Nothing is built, files are copied as they are, without `.git`, `.github`, `target`, `bin`, `node_modules`, `vendor` and `__links`.

One time setup: repository **Settings → Pages → Build and deployment → Source: GitHub Actions**. Until that is switched on the workflow fails on the deploy step.

There is no `index.html` in the repository, so the root address shows 404, files are reachable by their paths, e.g. `https://stopsopa.github.io/xx/templates/xx.ts`.

## Templates for `xx --init`

`xx --init [ts|js|mjs|cjs]` first downloads `init.json` (`https://raw.githubusercontent.com/stopsopa/xx/main/init.json`, can be replaced with `XX_INIT_CONFIG`), then the template listed there under the requested key (`templates/xx.<kind>` on `main`). Nothing is embedded in the binary, so changing a template means only: edit the file in `templates/`, push to `main`. No release needed.

The four templates have the same commands, they differ in the header, in `export default` / `module.exports` and `xx.ts` has types. When you change one, change all four.
