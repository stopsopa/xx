Test 024 verifies `xx --env`: the table `name | value | default | final` of all env vars `xx` reacts to.

- Everything defined: `~/` expanded in the last column, node version shown, `XX_NODE_OPTIONS` (also empty) replaces `NODE_OPTIONS`.
- Only required ones defined: `not defined` in the value column, defaults in the last one.
- Wrong `XX_NODE_BINARY`: the table is still printed, the reason under it, exit code 1.
- Wrong `XX_BIN`: no table (the binary prints it), `xx.sh` prints its error and the raw values, exit code 1.
- `--env` followed by anything else is a name of a command like any other.
