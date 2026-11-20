Test 022 verifies env vars controlling node.

`XX_NODE_BINARY` is required and checked on every run which needs node (`xx <name>`, `--list`, `--gen`, `--init`, `--esm`, also through `xx.sh`). Each case ends with exit code 1 and an error explaining what is wrong:

- not defined (node available in `PATH` is not used as a fallback),
- points to nothing,
- points to a file which can't be executed,
- points to a program which is not node (a script created by the test; not `/bin/echo`, which on some systems answers `--version` with its own version): the check runs `<binary> --version` and expects `vX.Y.Z`.

`~/` at the beginning of the path means home directory, the error shows the expanded path.

`--help` and `--version` work without it.

`XX_NODE_OPTIONS`: when not defined `NODE_OPTIONS` from the environment reaches node untouched. When defined (also as empty string) node started by `xx` gets its value as `NODE_OPTIONS`. Broken options are reported by the same check.
