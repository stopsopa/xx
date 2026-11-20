Test 003 verifies where the script of selected command is written:

- no `.git`: `${XX_TMP}/xx-<uid>/<hash of pwd>.sh`, in a directory private for the user (`drwx------`). The same directory always gives the same file, another directory gives another file, so two `xx` running at once in different directories can't overwrite each other's script. Nothing is written to home (the old `~/xx_generated.sh`).
- `XX_TMP` not defined: `TMPDIR` of the system is used instead; when both are defined `XX_TMP` wins.
- `.git` exists: `.git/xx_generated.sh`, no matter if the config is `./xx.cjs` or `.git/xx.cjs`.
- config from `~/xx.cjs`: the tmp file again.
- `.git` being a file (worktree, `gitdir: ...`) is resolved to the real git directory.
- the tmp directory writable by other users is refused (somebody else could swap the script).
