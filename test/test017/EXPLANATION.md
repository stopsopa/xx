Test 017 verifies the contract between `xx.sh` and the binary, in bash and in zsh.

The build (`bash/embed.sh`, called by `compile.sh` and by the release workflow) embeds md5 of the binary in `xx.sh`. `xx.sh` computes md5 of the file from `XX_BIN` before every use and refuses to continue (return code 1, nothing executed) when:

- `XX_BIN` is not defined (the binary is never searched or guessed),
- `XX_BIN` points to nothing,
- `XX_BIN` points to a file which is not executable,
- `XX_BIN` points to another program: the error shows both md5 and what the program answered to `--version`,
- `XX_BIN` points to a real xx binary which is not the one `xx.sh` was built with (a copy with one line appended): the error shows version of `xx.sh` and version of the binary,
- `xx.sh` is the source file from the repository, with no md5 embedded.

A wrapper built for several binaries (what a release has: one `xx.sh` for all platforms) accepts each of them.

The test also guards the two lines `bash/embed.sh` rewrites (`__XX_VERSION="dev"` and `__XX_BIN_MD5=""` in `xx.sh` of the repository).

`xx --version` prints version of both parts, version of `xx.sh` also when the binary is missing. `--lock` is no longer treated specially.
