Test 019 verifies that the config is found in `.git/` under every accepted name, one at a time: `.git/xx.ts`, `.git/xx.js` (written as ES module and as CommonJS), `.git/xx.mjs`, `.git/xx.cjs`.

For each of them: `xx --list` shows its command, `xx --gen` generates the script and `xx <name>` through `xx.sh` executes it in bash and in zsh. `xx.ts` contains real type annotations, so it proves node strips the types.
