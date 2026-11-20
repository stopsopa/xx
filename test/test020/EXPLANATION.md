Test 020 verifies that the config is found in the current directory under every accepted name, one at a time: `./xx.ts`, `./xx.js` (written as ES module and as CommonJS), `./xx.mjs`, `./xx.cjs`. Once without `.git` and once with empty `.git` next to it.

For each of them: `xx --list` shows its command, `xx --gen` generates the script and `xx <name>` through `xx.sh` executes it in bash and in zsh.

When no config exists anywhere the error names all four file names and all directories which were checked.
