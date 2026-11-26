Test 026 verifies `xx --config <path>` and `XX_CONFIG`: the config is pointed directly and used from another directory.

The config lives in one directory (with a space in its name) together with a script it calls, `xx` is called in other directories which have their own `./xx.cjs`, `.git` and `~/xx.cjs`: none of them may be used.

- Path: file with any name, `--config=<path>`, relative path, `~/`, directory (`xx.*` in it, not in its `.git/`), `XX_CONFIG`, argument wins over the env var, empty `XX_CONFIG` means not defined.
- Errors with the absolute path and exit code 1: missing file, directory without config, unsupported extension, `--config` without a path, broken config. No fallback to `./xx.cjs`.
- `--init` / `--esm` with `--config` are refused.
- `ctx.args` (without `--config`), `ctx.cwd`, `ctx.configPath`, `ctx.configDir`, relative `require` in the config, `ctx.configDir` without `--config`.
- Generated script: in the temp directory, one file per (directory, config), nothing in `.git` of the current directory changes and nothing is written next to the config. Without `--config` it is where it always was.
- Menu shows the path of the config only when it was pointed directly; `--env`, `--help`.
- Through `xx.sh` in bash and zsh: the command is executed in the directory `xx` was called in, the script never gets `--config`, `--config` after the name goes to the command, `--list` / `--gen` / `--env`, the menu with `--`, `confirm: true`, `source: true`.
- Nested call: `--config` is not inherited, exported `XX_CONFIG` is.
