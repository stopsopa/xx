---
name: xx
description: Work with xx (https://github.com/stopsopa/xx) - a menu of project shell commands defined in xx.ts / xx.js / xx.mjs / xx.cjs. Use when a project has an xx.* file (also in .git/), when the user says "xx <something>" or "run it through xx", or asks to add, change, explain or run a command from the xx menu.
license: GPL-2.0-only
metadata:
  author: stopsopa
  version: "1.1.0"
  website: https://github.com/stopsopa/xx
  created: "2026-11-23 00:07:53"
---

# xx

`xx` is a per-project menu of named shell commands. The config is a JS/TS file exporting a function which returns `{ "command name": { command: "<bash script>", ... } }`. A human types `xx` (interactive menu) or `xx <name> [args]`; the script of that command is written to a file and executed with `/bin/bash`.

The xx menu is usually the best list of "how things are done in this project" (build, test, deploy...). Read it before inventing your own commands.

## Which file is used

First found wins:

1. `--config <path>` or env var `XX_CONFIG` (the argument wins): only that config is used, everything below is skipped, no fallback. `<path>` is a file (any name, extension `.ts` `.js` `.mjs` `.cjs`) or a directory containing `xx.*`; relative to the current directory, `~/` means home.
2. `.git/xx.ts`, `.git/xx.js`, `.git/xx.mjs`, `.git/xx.cjs` (private, not committed)
3. `./xx.ts`, `./xx.js`, `./xx.mjs`, `./xx.cjs` (shared with the team)
4. `~/xx.*` (only when nothing above exists)

2 to 4 look only in the current directory (no walking up). A file in `.git/` hides the one in `./` completely, they are not merged. If the menu is not what you expect, check `XX_CONFIG` (`"$XX" --env`) and `.git/` first.

`--config` separates "where the config is" from "where the command works": the command is always executed in the directory xx was called in. It is how one config of general purpose tools is used from any project, usually through an alias the user has (`alias ai='xx --config "/path/to/ai/xx.ts"'`). An alias doesn't exist in your shell: when the user says "run `ai linkrepo`", call `"$XX" --config "/path/to/ai/xx.ts" linkrepo` in the directory they mean.

## Calling xx (you are not in an interactive shell)

`xx` is an alias (`source .../xx.sh`), so it does not exist in your shell, and the menu needs a terminal. Call the binary directly, its path is in `XX_BIN` (`~/` at the beginning means home):

```sh
XX="${XX_BIN/#\~/$HOME}"
```

If `XX_BIN` is not defined, xx is not installed for you: read the config file itself (see "Format") and tell the user.

### What commands exist and what they do

```sh
"$XX" --list            # number, name, description
"$XX" --list --json     # the same + confirm, source, order
"$XX" --gen "<name>"    # prints the exact bash script of the command, executes nothing
```

The config is code (env vars, template literals, shared snippets), so the source file may differ from the final script. `--gen` shows the script after all of that was evaluated, with the current environment. Always read it before running a command you don't know.

### Run a command

```sh
FILE="$(XX_CONFIRM=false "$XX" "<name>" arg1 arg2 < /dev/null)"; CODE="$?"
# CODE 0: run it.  CODE 55: the command has "source: true".  Anything else: error, already printed
[ "$CODE" = "0" ] && /bin/bash "$FILE" arg1 arg2
```

- Arguments are passed twice on purpose: to the binary (the config sees them as `ctx.args`) and to the script (`${1}`, `${2}`).
- `XX_CONFIRM=false` skips the "Run command?" question of commands with `confirm: true`, which would fail without a terminal.
- stdin of the script is yours to use: `echo data | /bin/bash "$FILE"`.
- `source: true` commands (exit code 55) are meant to change the user's interactive shell (`cd`, `source venv/bin/activate`, `export`). Sourcing them in your shell has no effect for the user: tell the user to run `xx <name>` instead.
- Env vars for the config are set on the binary: `ENVFILE=.env.ci "$XX" --gen "docker up"`.
- With another config, `--config <path>` goes first and only to the binary, never to the script (it is not an argument of the command). It works the same with `--list` and `--gen`:

  ```sh
  FILE="$(XX_CONFIRM=false "$XX" --config "/path/to/xx.ts" "<name>" arg1 < /dev/null)" && /bin/bash "$FILE" arg1
  ```

  Run it in the directory the command should work on: the script is executed where you are, not where the config is.

Commands can be destructive or outward-facing (deploy, publish, delete). `confirm: true` is the author's hint that it needs care, but most configs don't set it (the default is `false`), so its absence proves nothing: read the script and ask the user before running such a command.

## Format

```ts
// xx.ts - "export default". In xx.cjs: "module.exports = (setup, ctx) => { ... }"
export default (setup, ctx) => {
  // may be async. ctx = { args, cwd, configPath, configDir }
  return {
    "docker up": {
      command: `
set -e
docker compose --env-file "${process.env.ENVFILE || ".env"}" up -d
echo "first argument: \${1}"
`,
      description: `start all containers`,
      confirm: true,
      source: false,
      order: 10,
    },
    ...setup,
  };
};
```

Fields of a command, only `command` is required:

| Field         | Type    | Default             | Meaning                                                                                                                                                            |
| ------------- | ------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `command`     | string  | required            | Shell script, written to a file and executed with `/bin/bash`. Arguments of `xx` are its `${1}`, `${2}`...                                                         |
| `description` | string  | name of the command | Shown under the menu for the selected row.                                                                                                                         |
| `confirm`     | boolean | `false`             | `false`: run straight away. `true`: ask "Run command?" first. Only `true` asks, any other value means `false`. `XX_CONFIRM=false` skips the question.              |
| `source`      | boolean | `false`             | `false`: executed with `/bin/bash` as a separate process. `true`: sourced in the user's current shell, so `cd`, `export`, `source venv/bin/activate` stay applied. |
| `order`       | number  | `0`                 | Lower goes first: negative = top, positive = bottom. The same `order`: order of the file.                                                                          |

`<% name %>` in `command` and `description` is replaced with the name of the command.

`ctx`, the second argument of the function:

| Field        | What it is                                                                                               |
| ------------ | -------------------------------------------------------------------------------------------------------- |
| `args`       | Arguments given after the name of the command (never `--config <path>`).                                 |
| `cwd`        | Directory xx was called in. The script is executed there.                                                |
| `configPath` | Absolute path of the config in use.                                                                      |
| `configDir`  | Absolute path of its directory. The way to reach files living next to the config, never a relative path. |

```ts
linkrepo: {
  // the script lives next to the config, it works on the directory xx was called in
  command: `/bin/bash "${ctx.configDir}/xx/linkrepo.sh" "\${@}"`,
},
```

Relative `import` / `require` inside the config resolve relative to the config file, as in any module. Relative paths inside `command` resolve relative to the directory xx was called in, which with `--config` is not the directory of the config: use `ctx.configDir`.

In xx before v0.6.0 the default of `confirm` was `true` (ask), which is why older configs say `confirm: false` in every command. That line is redundant now: don't add it to new commands, leave it alone in existing ones.

The trap when writing commands: `command` is a JS template literal which becomes a bash script.

- `${x}` is evaluated by node when the config is loaded.
- `\${x}` and `\$(...)` are left for bash. Every bash variable and command substitution has to be escaped like that.
- A backslash meant for bash has to be doubled (`\\n`, `\\.`).

Order of the menu: sorted by `order`, and the sort is stable, so commands with the same or missing `order` are shown in the order they were defined.

## Structure of a good config

- Names: short, as a human would type them, spaces are fine (`docker up`, `db migrate`). Related commands share a prefix so they sit together and filter well.
- One command = one task. Start multi-line scripts with `set -e`.
- `description` says what it does in one line; mention arguments it takes.
- `confirm: true` for anything destructive or outward-facing (deploy, publish, delete, reset). Leave the default (`false`, no question) for everything else.
- `source: true` only when the command has to change the user's shell.
- Shared pieces of script go to constants above `export default` and are interpolated with `${...}`.
- The list of commands is a flat literal object, not generated by code (rules 2 and 3 below).
- Keep the existing style and module format of the file (`.cjs` is CommonJS, `.mjs` ES module, `.ts`/`.js` follow the project).

## Installing a config in a project ("add xx to this project")

Never write the file from scratch, bring the template (it refuses to overwrite an existing file):

```sh
"$XX" --init            # .git/xx.ts if .git exists (private, not committed), else ./xx.ts
"$XX" --esm ./xx.ts     # ./xx.ts - committed, shared with the team
"$XX" --init cjs        # the same template as xx.cjs, when node is older than 22.18
```

Before creating it ask the user where the config should live, unless they already said:

- **in the repository** (`./xx.ts`): committed, the whole team gets the same menu.
- **only for them** (`.git/xx.ts`): never committed, invisible to others. This is where `--init` puts it by default.

Changing the mind later is just moving the file one directory up or down (`mv .git/xx.ts xx.ts`), nothing else refers to its location. Only one of them may exist: the one in `.git/` hides the one in `./`.

The template is a showcase of examples, not a config to keep. After downloading it:

1. Remove every command except `help`. Leave the top of the file exactly as it came (rule 1 below).
2. Rewrite `help`: it is the "what is this project" card. Keep the line which prints the link to the repository, delete the example content (admin urls, dev notes) and put there what is true for this project: link to the repository (usually GitHub; the line in the template derives it from `git ls-remote --get-url origin`, check that it prints a working link for this remote), docs, local urls, anything worth having at hand.
3. Add the commands the user asked for (see "Structure of a good config").
4. Make sure the `Command` type carries the description of every field (rule 1 below).
5. Verify (see "After editing the config").

## Rules for the file created from the template

These three rules apply every time you create a config with `--init` / `--esm`, and every time you later edit one which came from the template.

### 1. Never touch the top of the file

The template starts with this comment:

```ts
// github edit  : https://github.com/stopsopa/xx/edit/main/templates/xx.ts
```

Leave that line and everything below it, down to the `export default`, exactly as downloaded: the comments (env var hint, emoji, how to call xx from xx), `S`, the color constants, the `enter` / `esc` snippets and the `Command` / `Commands` / `Ctx` types.

- Don't delete, reword, reorder or "clean up" any of it, also when the commands you write don't use it. Unused constants are fine here.
- The `github edit` link says where the file came from and is how the user gets to the template: it stays the first line of the file.
- Your own constants go below that block, right above `export default`.

The `Command` type is the documentation of the format for a human who opens the file, so it has to describe every field: what it is, its default and what each value does. The current template comes like this:

```ts
type Command = {
  // required. Shell script, written to xx_generated.sh and executed with /bin/bash
  command: string;
  // default: name of the command. Shown under the menu for the selected row
  description?: string;
  // default: false = run straight away
  // true = ask "Run command?" first (XX_CONFIRM=false skips the question)
  confirm?: boolean;
  // default: false = executed with /bin/bash as a separate process
  // true = sourced in the current shell (cd, export, source venv/bin/activate stay after it ends)
  source?: boolean;
  // default: 0. Lower goes first: negative = top, positive = bottom
  // commands with the same order stay in the order of this file
  order?: number;
};
```

This is the one exception to "exactly as downloaded": when the `Command` type in the file has no such comments, or they say something else (a bare type, or an older template saying `confirm` defaults to `true`), replace the type with the block above. Do it when you create a config and whenever you edit one. Nothing else at the top changes, `Commands` and `Ctx` stay as they are.

A config in plain JavaScript (`xx.js`, `xx.mjs`, `xx.cjs`) has no types: leave it without them.

The only part of the file you rewrite is the body of the exported function: the object it returns.

### 2. The list of commands stays flat

Define commands the way the template presents them: one literal object, one literal key per command, each with its script written out in full, and `...setup` at the end.

```ts
export default (setup: Commands, ctx: Ctx): Commands => {
  return {
    [`docker up`]: {
      command: `
set -e
docker compose up -d
`,
      description: `start all containers`,
      confirm: false,
    },
    [`docker down`]: {
      command: `
set -e
docker compose down
`,
      description: `stop all containers`,
      confirm: false,
    },
    ...setup,
  };
};
```

Don't be clever. Don't assemble the list programmatically:

- no loops, `map` / `reduce` / `Object.fromEntries` generating commands from an array,
- no helper or factory functions returning a command object or a script (`cmd("docker", "up")`, `add(name, script)`, `run(script)`),
- no commands split into separate objects or files and merged with spread,
- no computed names, no conditions adding or removing commands.

Two almost identical commands are written as two commands. Repetition is the point: a human opens the file, searches for the name seen in the menu and reads the whole script in one place, top to bottom, and can change one command without thinking about the others.

Interpolating a constant or a snippet into a script (`${enter}`, `${GREEN}`) is fine, that is what the top of the file is for. What has to stay flat is the list itself.

The only exception is rule 3.

### 3. When part of the list has to be generated after all

Reach for code only when it is really justified (almost always it is not):

- the list can't be known at the time of writing, or
- the same group of commands repeats for several things (`typescript`, `rust`, `bash`...) and differs only by one name. Two or three similar commands are not a reason, write them out.

If you think you hit such a case, tell the user and ask before doing it.

Then keep it as close to the flat list as possible. Of rule 2 only this is relaxed: one plain `for ... of` loop over a literal array, the loop variable in names and scripts, and merging with spread. Everything else still holds.

- One main object, built top to bottom **in the order of the menu**: reading the file from the top gives the menu from the top.
- Everything which is not repeated stays a literal entry, exactly as in rule 2.
- Each pass of the loop creates a new helper object and merges it into the main one. What comes after the loop is merged in the same way.
- The helper object is written like any other group of commands: literal keys, the whole script, the whole description. Only the loop variable differs from a normal entry.
- No conditions inside the loop (`if (part !== "tests")`). A thing which has only some of the commands is not part of the loop: write its commands as literal entries.
- Don't put the loop above the main object and spread its result into the middle: definitions would no longer be in the order of the menu.

```ts
export default (setup: Commands, ctx: Ctx): Commands => {
  // 1. main object: commands shown before the generated group
  let commands: Commands = {
    [`install`]: {
      command: `
set -e
./install.sh "\${@}"
`,
      description: `install dependencies of all parts  [./install.sh]`,
      confirm: false,
    },
  };

  // 2. generated group: one helper object per pass, merged into the main one
  for (const part of [`typescript`, `rust`, `bash`]) {
    const helper: Commands = {
      [`${part} compile`]: {
        command: `
set -e
./${part}/compile.sh "\${@}"
`,
        description: `compile ${part}  [./${part}/compile.sh]`,
        confirm: false,
      },
      [`${part} test`]: {
        command: `
set -e
./${part}/test.sh "\${@}"
`,
        description: `unit tests of ${part} only  [./${part}/test.sh]`,
        confirm: false,
      },
    };

    commands = { ...commands, ...helper };
  }

  // 3. commands shown after the generated group
  commands = {
    ...commands,
    [`report open`]: {
      command: `
set -e
open tests/out/report/index.html
`,
      description: `open the report of the last test run`,
      confirm: false,
    },
  };

  return { ...commands, ...setup };
};
```

Preserving the order:

- No command in the file has `order`: building the main object top to bottom is enough (the sort is stable, see "Format").
- The file uses `order`: every generated command needs one too, otherwise it lands at 0, above everything else. Declare a counter right before the loop, starting at the first free number, and write `order: order++` in each entry. Entries of an object literal are evaluated top to bottom, so the numbers follow the definitions. Commands after the loop continue from the next number.
- Never compute `order` from the index of the loop or from the name.

When converting an existing config between the flat and the generated form, compare the menu before and after: `"$XX" --list --json` and `"$XX" --gen` of every command must give exactly the same output.

## After editing the config

```sh
"$XX" --list            # the config still loads, the command is there
"$XX" --gen "<name>"    # the script is exactly what you intended (escaping!)
```

Errors of the config (syntax, wrong shape) are printed by `--list` with the path of the file.

## Other

- `"$XX" --env` shows all `XX_*` env vars with final values, `"$XX" --help` everything else.
- Setup problems (`XX_NODE_BINARY`, md5 mismatch between `xx.sh` and the binary) and `xx --update` are for the user to handle in their own terminal.

# Migration and Automigration

I have permanently switched to new implementation of xx tool which preferably uses xx.ts not xx.cjs.

So every time I will ask you to interact with xx config then first pay attention if config is defined as xx.ts

if it is xx.cjs then migrate all content from xx.cjs to xx.ts and remove xx.cjs.

and apply all rules from this skill file. but don't drop any commands, keep them as is.

Bring new header extracted from freshly pulled xx.ts -> see section

to obtain fresh init template execute

```sh

(d="$(mktemp -d "$PWD/xx-tmp-XXXXXX")" && trap 'rm -rf "$d"' EXIT && cd "$d" && xx --init && head -n 100 xx.ts)

```

The header includes the `Command` type with the description of every field (see rule 1), the migrated xx.ts has to have it too.

once you extract top comment put it in our new (result of migration) xx.ts and stop with whatever you do and aks user to commit changes.

After committing migration is complete.

And express explicitly to continue. Only then continue witch what you have been asked to do.

## When asked HOW to migrate

When the user only asks how to migrate (e.g. "how to migrate xx.cjs to xx.ts"), don't explain the steps and don't start the migration. Always answer just with something like this, with the absolute path of the config found in the current project:

```
The xx skill has the procedure of migration described, you just have to ask me to migrate here.
Would you like to migrate '/absolute/path/to/xx.cjs' to xx.ts?
```

Only when the user confirms (or asks to do the migration in other words) do the migration as described above.
