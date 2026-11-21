Test 025 verifies `xx --update`: `xx.sh` and the binary are replaced together from a release, or nothing is replaced at all.

Releases are faked in a local directory (`XX_RELEASES`) with the layout GitHub has. Two binaries with real versions are built for the test (`v9.9.8`, `v9.9.9`), because a `dev` build refuses to update.

- `--update --check` only reports installed and latest version.
- Answer "no": nothing changes.
- Release with a file not matching `SHA256SUMS.txt`: refused, nothing changes.
- Release where checksums are fine but `xx.sh` was built for another binary: caught by the test of the pair before anything is replaced.
- Release which doesn't exist: error, nothing changes.
- Real update (from bash) and install of an older given tag (from zsh): both files are byte for byte the ones from the release, no temporary files are left, `xx.sh` keeps its permissions, `xx --version` and a command work in bash and zsh afterwards.
- Already the latest: "xx is up to date".
- The binary executed directly (without `xx.sh`) and a `dev` build refuse to update.
