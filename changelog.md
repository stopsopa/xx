# Release Notes

Each release has its own `## vX.Y.Z` section. The release workflow copies the section matching the pushed tag to the top of the GitHub release page (`bash/release_notes.sh`), so add the section before running `tag.sh`.

## v1.0.0

### Rewrite in Rust

First release of `xx` as a Rust binary + `xx.sh` wrapper. It replaces the node + inquirer implementation from `stopsopa.github.io/pages/bash/xx`. Existing `xx.cjs` files work without changes, the installation is different (see `README.md`).

- **Menu**: drawn by the binary itself (no inquirer, no bundle). Selected row in reverse colors, block indicator, description under the list. New: type to filter rows by name or number.
- **Config**: `xx.ts`, `xx.js`, `xx.mjs`, `xx.cjs` are accepted, searched in this order in `.git/`, then in the current directory, then in home. `xx.ts` is executed by node directly (22.18+). `xx.js` can be ES module or CommonJS. The function may be async, gets context `(setup, { args, cwd, configPath })` as second argument, output printed by the config goes to stderr.
- **`XX_NODE_BINARY`** (required): path to node, checked on every run. `node` from `PATH` is not used.
- **`XX_NODE_OPTIONS`**: replaces `NODE_OPTIONS` for node started by `xx`. Without it `NODE_OPTIONS` is passed untouched.
- **`XX_BIN`** (required): `xx.sh` verifies on every call that `XX_BIN` is one of the binaries it was built with: md5 of the binaries of the release is embedded in `xx.sh`.
- **Arguments**: `xx <name> [args]` as before, new `xx -- [args]` opens the menu and passes args to the picked command.
- **Stdin**: `echo data | xx <name>` reaches the final script (the menu talks to `/dev/tty`, config is loaded with stdin closed).
- **`source: true` and Ctrl+C**: Ctrl+C no longer closes the terminal when the sourced script uses `set -e`. `set -e` is neutralised in sourced scripts, Ctrl+C stops the script and returns 130. Works in bash 3.2, bash 5 and zsh.
- **`--init [ts|js|mjs|cjs]`**: default `ts`. Templates are always downloaded, from locations listed in `init.json` on GitHub; `XX_INIT_CONFIG` (URL or local path) replaces that list.
- **`--esm [path]`**: the `xx.ts` template written to given file or directory.
- **Generated script without `.git`**: `${XX_TMP}/xx-<uid>/<hash of pwd>.sh` instead of `~/xx_generated.sh` shared by all terminals (`XX_TMP` falls back to `TMPDIR`, then `/tmp`).
- **`XX_CONFIRM=false`**: new name of `XXCONFIRM=false`, the old name is not read anymore.
- **`--gen`**: fixed, it was treated as a command name before.
- **`xx <number>`**: number now means the number shown in the menu (after sorting by `order`), before it was position in the file.
- **`order`**: deterministic: stable sort, missing `order` counts as 0.
- **Git worktrees**: `.git` being a file is resolved to the real git directory.
- **`--lock` / `--unlock` / `--copy`**: removed.
- **`--list [--json]`**, **`--version`**: new.
