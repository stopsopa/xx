Test 017 verifies the contract between `xx.sh` and the binary, in bash and in zsh.

The binary answers `xx --handshake` with `xx-handshake:1:<version>`. `xx.sh` checks it before every use and refuses to continue (return code 1, nothing executed) when:

- `XX_BIN` is not defined (the binary is never searched or guessed),
- `XX_BIN` points to nothing,
- `XX_BIN` points to a file which is not executable,
- `XX_BIN` points to another program (its answer is shown in the error),
- version of `xx.sh` differs from version of the binary (both are shown). The other version is produced the same way the release workflow embeds the tag: by replacing the line `__XX_VERSION="dev"`, so the test also guards that line.

`xx --version` prints version of both parts, version of `xx.sh` also when the binary is missing. `--lock` is no longer treated specially.
