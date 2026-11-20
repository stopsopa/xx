# xx

**One menu for all the shell commands of your project.**

Every project collects commands nobody remembers: start the containers with the right env file, run the migration, activate the virtualenv, tail that one log. `xx` keeps them in one file next to the project and puts them one keystroke away:

```
$ xx
? Select command to run
❯ █   1 - help
  ▏   2 - docker up
  ▏   3 - db migrate
  █   4 - activate

Status of all things
↑↓ navigate • ⏎ select • type to filter
```

Type `xx`, pick a command with the arrows (or type to filter), press Enter, it runs. Or skip the menu: `xx "docker up"`.

The menu comes from a small config file in your project, `xx.ts`:

```ts
export default () => ({
  "docker up": {
    command: `docker compose --env-file "${process.env.ENVFILE || ".env"}" up -d`,
    description: `start all containers`,
  },
  activate: {
    command: `source venv/bin/activate`,
    source: true, // runs in your current shell, so the virtualenv stays active
    confirm: false,
  },
});
```

## Why xx

- **The config is real code.** TypeScript or JavaScript, executed by node: build the scripts from env vars, shared snippets, loops, imports. No YAML, no template language.
- **Commands can change your current shell.** With `source: true` a command is sourced instead of executed, so `cd`, `export` or `source venv/bin/activate` still apply after it ends. Ctrl+C in such a command does not close your terminal.
- **Behaves like a normal command.** Arguments and stdin reach the script (`xx build --fast`, `cat dump.sql | xx "db import"`), its exit code comes back.
- **Asks before running**, unless the command says `confirm: false`.
- **Private or shared, your choice.** Put the config in `.git/xx.ts` to keep it only for yourself, or in `./xx.ts` to commit it for the team.
- **Fast and dependency free.** A small Rust binary draws the menu. Nothing to `npm install`, no bundle.

## Requirements

- macOS (Apple silicon) or Linux (x64, arm64)
- bash or zsh
- node (22.18+ if the config is `xx.ts`; older versions work with `xx.js`, `xx.mjs`, `xx.cjs`)

## How it works

`xx` is two files, always from the same release:

- `xx-bin`, a Rust binary: finds the config, asks node to load it, shows the menu and writes the script of the picked command to a file.
- `xx.sh`, a shell wrapper sourced through an alias: executes that file. This split is what makes `source: true` possible, only the shell itself can source a script into itself. The wrapper works only with the binaries of its own release.

## Contents

- [Installation](#installation)
- [Usage](#usage)
- [Config](#config): where it is searched, file formats, all options
- [Environment variables](#environment-variables)
- [Arguments and stdin](#arguments-and-stdin)
- [`source: true`](#source-true)
- [Exit codes](#exit-codes)
- [Development](#development)

## Installation

### 1. Download and verify

Go to [GitHub Releases](https://github.com/stopsopa/xx/releases), open the release you want (the latest one normally) and run the block for your platform. It creates a new temporary directory, `cd`s into it, downloads two files there and verifies checksums of both:

- `xx-bin` - the binary for your platform
- `xx.sh` - the wrapper

Both lines of the verification have to end with `OK`. Then come back here, **in the same terminal** (you are in the directory with the two files).

### 2. Install

In the directory with the two downloaded files:

```sh
mkdir -p ~/.xx
cp xx-bin xx.sh ~/.xx/
chmod 755 ~/.xx/xx-bin
chmod 644 ~/.xx/xx.sh
```

Add four lines to the startup file of your shell. Run **one** of the two blocks, once: the first is for zsh (`~/.zshrc`), the second for bash (`~/.bashrc`) (it resolves the path of `node` you are using right now and writes it as a fixed path):

```sh
cat <<EEE >> ~/.zshrc

# xx - https://github.com/stopsopa/xx
export XX_BIN="~/.xx/xx-bin"
export XX_NODE_BINARY="$(node -e 'const p = process.execPath, h = require("os").homedir(); console.log(p.startsWith(h + "/") ? "~" + p.slice(h.length) : p)')"
export XX_NODE_OPTIONS=
alias xx='source ~/.xx/xx.sh'
EEE
```

```sh
cat <<EEE >> ~/.bashrc

# xx - https://github.com/stopsopa/xx
export XX_BIN="~/.xx/xx-bin"
export XX_NODE_BINARY="$(node -e 'const p = process.execPath, h = require("os").homedir(); console.log(p.startsWith(h + "/") ? "~" + p.slice(h.length) : p)')"
export XX_NODE_OPTIONS=
alias xx='source ~/.xx/xx.sh'
EEE
```

What lands in the file (node installed with asdf as an example):

```sh
# xx - https://github.com/stopsopa/xx
export XX_BIN="~/.xx/xx-bin"
export XX_NODE_BINARY="~/.asdf/installs/nodejs/24.12.0/bin/node"
export XX_NODE_OPTIONS=
alias xx='source ~/.xx/xx.sh'
```

`XX_NODE_OPTIONS=` keeps `NODE_OPTIONS` of your shell (a debugger, memory flags...) away from node started by `xx`, see [Environment variables](#xx_node_options).

`~/` at the beginning of a path means your home directory. Inside of quotes the shell leaves `~` as it is, `xx.sh` and the binary expand it themselves, in every path they read from env vars.

Open a **new terminal** and check that it works, without any path:

```sh
xx --help
xx --version     # prints version of xx.sh and of the binary, they have to be the same
```

Create the first config in your project and open the menu:

```sh
cd /path/to/project
xx --init     # downloads template to .git/xx.ts (./xx.ts if the directory is not a git repository)
xx
```

The files can live anywhere, `~/.xx` is only a suggestion: `XX_BIN` points to the binary, the alias points to `xx.sh`.

To update: repeat steps 1 and the `cp` + `chmod` part of step 2 with a newer release. Always replace both files: `xx.sh` refuses to work with any binary other than the ones of its own release.

After changing version of node (asdf, nvm...) update `XX_NODE_BINARY`, `xx` tells you when the path stops working.

## Usage

```sh
xx                          # open the menu
xx <name|number> [args]     # run command directly, number is the one shown in the menu
xx -- [args]                # open the menu and pass args to the picked command
echo data | xx <name>       # stdin goes to the script of the command

xx --gen [name|number]      # write and print the script, don't run it
xx --list [--json]          # print commands
xx --init [ts|js|mjs|cjs]   # download template of the config, default ts
xx --esm [path]             # download template xx.ts to given file or directory
xx --help
xx --version
```

In the menu: `↑` `↓` move (wraps around), `Home` `End` `PgUp` `PgDn`, `Enter` runs, typing filters rows by name or number, `Backspace` edits the filter, `Esc` clears the filter and second `Esc` (or `Ctrl+C`) cancels.

## Config

### Where it is searched

First found wins, checked in this order:

| # | Config | Generated script |
| --- | --- | --- |
| 1 | `.git/xx.ts`, `.git/xx.js`, `.git/xx.mjs`, `.git/xx.cjs` | `.git/xx_generated.sh` |
| 2 | `./xx.ts`, `./xx.js`, `./xx.mjs`, `./xx.cjs` | `.git/xx_generated.sh`, without `.git`: `${XX_TMP}/xx-<uid>/<hash of pwd>.sh` |
| 3 | `~/xx.ts`, `~/xx.js`, `~/xx.mjs`, `~/xx.cjs` | `${XX_TMP}/xx-<uid>/<hash of pwd>.sh` |

Only the current directory is checked, parent directories are not.

### Which extension, which module format

| File | Format | Depends on `package.json`? |
| --- | --- | --- |
| `xx.ts` | TypeScript, ES module: `export default` | like `xx.js`, see below |
| `xx.js` | ES module **or** CommonJS, your choice | yes |
| `xx.mjs` | always ES module: `export default` | no |
| `xx.cjs` | always CommonJS: `module.exports =` | no |

Rules of node apply, `xx` adds nothing of its own. For `xx.js` and `xx.ts` node looks at `"type"` in the nearest `package.json` (for `.git/xx.js` that is `package.json` of the project):

| `"type"` in `package.json` | `xx.js` / `xx.ts` has to be written as |
| --- | --- |
| no `package.json`, or no `"type"` in it | either one, node detects it from the syntax |
| `"module"` | ES module |
| `"commonjs"` | CommonJS |

So `xx.ts` with `export default` works everywhere except a project which says `"type": "commonjs"` explicitly. `xx.mjs` and `xx.cjs` are the way to force the format no matter what `package.json` says.

`xx.ts` is executed by node directly (node removes the types, nothing is compiled or type checked). It needs node 22.18 or newer, and only erasable syntax: no `enum`, no `namespace`, no parameter properties.

### Format

```ts
// xx.ts
type Command = {
  command: string;
  description?: string;
  confirm?: boolean;
  source?: boolean;
  order?: number;
};

type Ctx = { args: string[]; cwd: string; configPath: string };

export default (setup: Record<string, Command>, ctx: Ctx): Record<string, Command> => {
  return {
    "docker up": {
      // required: shell script, written to xx_generated.sh and executed with /bin/bash
      command: `
set -e
docker compose --env-file "${process.env.ENVFILE || ".env"}" up -d
echo "first argument: \${1}"
`,
      // optional: shown under the menu for selected row. Default: name of the command
      description: `start containers of <% name %>`,
      // optional: default is true = ask "Run command?" before running
      confirm: false,
      // optional: default is false. true = run in the current shell (source) instead of /bin/bash
      source: false,
      // optional: lower goes first. Missing means 0, so negative = top, positive = bottom
      order: 10,
    },
    activate: {
      command: `source venv/bin/activate`,
      confirm: false,
      source: true,
    },
    ...setup,
  };
};
```

The same in CommonJS (`xx.cjs`, or `xx.js`): `module.exports = (setup, ctx) => { ... }`.

- It is plain JavaScript executed by node, so the script can be built any way you like: `process.env`, imports, shared snippets, computed names. `${...}` is filled when the config is loaded, `\${...}` is left for bash.
- The function can be `async` (can return a Promise).
- `ctx` is `{ args, cwd, configPath }` - arguments given after the name of the command, current directory, path of the config.
- `<% name %>` in `command` and `description` is replaced with the name of the command.
- Rows are numbered after sorting by `order`, `xx 3` runs the row shown as 3 in the menu.
- Anything the config prints (`console.log`) goes to stderr.

## Environment variables

In every variable holding a path, `~/` at the beginning means your home directory (the shell doesn't expand `~` inside of quotes, so `xx` does).

| Variable | Required | Read by | What it expects |
| --- | --- | --- | --- |
| `XX_BIN` | yes | `xx.sh` | Path to the xx binary. |
| `XX_NODE_BINARY` | yes | binary | Absolute path to the node binary. |
| `XX_NODE_OPTIONS` | no | binary | Value for `NODE_OPTIONS` of node started by `xx`. |
| `XX_INIT_CONFIG` | no | binary | URL or path of json listing where the templates are. |
| `XX_CONFIRM` | no | binary | `false` skips every "Run command?" question. |
| `XX_TMP` | no | binary | Directory for generated scripts when there is no `.git`. |

### `XX_BIN`

Path to the xx binary (`xx-bin` from the release), `~/` at the beginning means home directory. Required, nothing is searched or guessed. `xx.sh` checks it on every call and refuses to continue, explaining why, when:

- it is not defined, points to nothing, or the file is not executable,
- md5 of the file is not one of the hashes embedded in `xx.sh`. Every `xx.sh` is built together with its binaries and carries their md5, so it accepts only them: another program, a binary of another version, a modified or half downloaded file are all refused. To make the reason easier to see the error also shows version of `xx.sh` and what the file answers to `--version`.

In practice: always replace both files together.

### `XX_NODE_BINARY`

Absolute path to the node binary used to load the config. Required, `node` from `PATH` is **not** used as a fallback: with version managers (asdf, nvm, volta...) `node` in `PATH` is often a shim which depends on the current directory and is slow to start. A fixed path means the config is always loaded by the node you chose.

Checked on every run (except `--help` and `--version`): the file has to exist and `"${XX_NODE_BINARY}" --version` has to print `vX.Y.Z`. Otherwise `xx` stops immediately with a message saying what is wrong.

```sh
# path of node you are using right now
node -e 'console.log(process.execPath)'
```

`~/` at the beginning means home directory: `export XX_NODE_BINARY="~/.asdf/installs/nodejs/24.12.0/bin/node"`.

Any version of node which can run your config is fine; `xx.ts` needs 22.18+.

### `XX_NODE_OPTIONS`

`NODE_OPTIONS` is the native variable of node with extra command line options.

- **not defined** (default): `xx` does nothing, node gets `NODE_OPTIONS` exactly as it is in your shell.
- **defined**: node started by `xx` gets `NODE_OPTIONS` set to this value. Defined as empty string it clears `NODE_OPTIONS`.

It affects only node which loads the config, not the script of the command (the script sees `NODE_OPTIONS` of your shell).

```sh
# NODE_OPTIONS="--inspect" in the shell prints "Debugger listening..." on every xx. Switch it off only for xx:
export XX_NODE_OPTIONS=""
```

### `XX_INIT_CONFIG`

Used by `xx --init` and `xx --esm`. URL (`http://`, `https://`) or path (also starting with `~/`) of a json file which says where the template of each kind is:

```json
{
  "ts": "https://example.com/templates/xx.ts",
  "js": "https://example.com/templates/xx.js",
  "mjs": "/absolute/path/to/xx.mjs",
  "cjs": "relative/to/this/json/xx.cjs"
}
```

- Each value is again a URL or a path of a local file (`file://` prefix is accepted). URL is downloaded with `curl` (`wget` when `curl` is not installed), local file is copied.
- Relative path inside of the json is relative to the json. Relative `XX_INIT_CONFIG` is relative to the current directory.
- Only the key of the requested kind has to be present.
- Default: `https://stopsopa.github.io/xx/init.json` (GitHub Pages of the repository). Templates are never embedded in the binary, what is published there is the source of truth, every `--init` gets the current version. Only `xx.ts` is written by hand, `xx.js`, `xx.mjs` and `xx.cjs` are generated from it when Pages are published.

### `XX_CONFIRM`

`XX_CONFIRM=false xx <name>` runs the command without the "Run command?" question, also when the command says `confirm: true`. Any other value changes nothing. (The old implementation called it `XXCONFIRM`, that name is not read anymore.)

### `XX_TMP`

When there is no `.git` directory the script of the picked command is written to `${XX_TMP}/xx-<uid>/<hash of pwd>.sh`. `XX_TMP` has to be an existing directory (`~/` at the beginning means home directory). When it is not defined the standard `TMPDIR` of the system is used, and `/tmp` when that is not defined either, so normally there is nothing to set.

The directory `xx-<uid>` is created private for the user (`700`), `xx` refuses to use it if it belongs to somebody else or is writable by others. One file per directory, so `xx` running in two directories at once don't overwrite each other's script.

## Arguments and stdin

Everything after the name of the command is passed to the script as `${1}`, `${2}`...:

```sh
xx "docker up" first "second with spaces"
xx -- first                 # pick the command from the menu, then run it with the argument
```

Stdin of `xx` is stdin of the script. The menu and the "Run command?" question read keys from the terminal directly, so they work also when stdin is a pipe:

```sh
cat dump.sql | xx "db import"
xx "db import" < dump.sql
```

## `source: true`

The script is sourced in your current shell, so `cd`, `export`, `source venv/bin/activate` stay after it ends.

- **Ctrl+C does not close the terminal.** It stops the script and returns to the prompt with code 130.
- **`set -e` is neutralised** in such scripts: in a sourced script it would close your terminal on first failing command. The script continues after a failed command, check results yourself where it matters (`command || return 1`).
- **Don't use `exit`**, it closes the terminal. Use `return`.
- In bash a pipe runs every part in a subshell, so `echo data | xx activate` can't change the current shell. Use redirection instead: `xx activate < file`.

## Exit codes

`xx` returns exit code of the executed script. Besides that: `130` cancelled, `10` "Run command?" answered with no, `1` error (config not found, broken config, unknown command, `XX_BIN` or `XX_NODE_BINARY` not passing the check).

## Development

See [DEV.md](DEV.md).
