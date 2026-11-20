Test 023 presents what happens when the contract between `xx.sh` and the binary is broken.

md5 embedded in a copy of the wrapper is changed (`__XX_BIN_MD5="000...0"`), then `xx --init` is called through that copy in an empty directory, in bash and in zsh. Expected:

- `xx.sh` stops with return code 1 before the binary is asked to do anything: no `xx.ts` is created,
- the error shows md5 of the file from `XX_BIN`, md5 the wrapper expects, version of `xx.sh` and what the binary answers to `--version`, and suggests that the two files come from different versions.

The same `xx --init` through the untouched wrapper creates `xx.ts`, which proves it was only the contract that stopped the first one.

The test prints the whole error message, so the output of `test.sh` shows how the situation looks for the user.
