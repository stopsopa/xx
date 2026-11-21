DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# xx --env: table of all env vars used by xx: name | value | default | final

echo 'module.exports = () => ({ "--env": { command: `echo executed-env "\${@}"`, confirm: false } });' > xx.cjs

NODE_VERSION="$("${XX_NODE_BINARY}" --version)"
mkdir "${HOME}/.xx"
cp "${BIN}" "${HOME}/.xx/xx-bin"
ln -s "${XX_NODE_BINARY}" "${HOME}/node"
UID_NOW="$(id -u)"

# row <output> <name>: one row of the table with columns squeezed to "a | b | c | d"
row() {
  echo "${1}" | grep "^${2} " | sed -E 's/ +\| +/ | /g'
}

for SHELL_BIN in /bin/bash zsh; do
  # everything defined
  OUT="$(
    XX_NODE_BINARY="~/node" XX_NODE_OPTIONS="" NODE_OPTIONS="--no-warnings" XX_BIN="~/.xx/xx-bin" \
      XX_INIT_CONFIG="~/init.json" XX_CONFIRM="false" XX_TMP="~/my tmp" TMPDIR="/from/tmpdir" \
      "${SHELL_BIN}" -c "source \"${XXSH}\" --env; echo \"code=\${?}\"" 2>&1
  )"
  assert_contains "${OUT}" "code=0" "${SHELL_BIN}: exit code, everything defined"
  assert_eq "$(row "${OUT}" name)" "name | value | default | final (used by xx right now)" "${SHELL_BIN}: header"
  assert_eq "$(row "${OUT}" XX_NODE_BINARY)" "XX_NODE_BINARY | >~/node< | none, required | >${HOME}/node< (node ${NODE_VERSION})" "${SHELL_BIN}: XX_NODE_BINARY"
  assert_eq "$(row "${OUT}" XX_NODE_OPTIONS)" 'XX_NODE_OPTIONS | >< | ${NODE_OPTIONS} | >< (XX_NODE_OPTIONS is defined, ${NODE_OPTIONS} is ignored)' "${SHELL_BIN}: XX_NODE_OPTIONS empty replaces NODE_OPTIONS"
  assert_eq "$(row "${OUT}" XX_BIN)" "XX_BIN | >~/.xx/xx-bin< | none, required | >${HOME}/.xx/xx-bin<" "${SHELL_BIN}: XX_BIN"
  assert_eq "$(row "${OUT}" XX_INIT_CONFIG)" "XX_INIT_CONFIG | >~/init.json< | https://stopsopa.github.io/xx/init.json | >${HOME}/init.json<" "${SHELL_BIN}: XX_INIT_CONFIG"
  assert_eq "$(row "${OUT}" XX_CONFIRM)" 'XX_CONFIRM | >false< | true | false (never ask "Run command?")' "${SHELL_BIN}: XX_CONFIRM"
  assert_eq "$(row "${OUT}" XX_TMP)" "XX_TMP | >~/my tmp< | \${TMPDIR}, then /tmp | >${HOME}/my tmp< (scripts in >${HOME}/my tmp/xx-${UID_NOW}<)" "${SHELL_BIN}: XX_TMP"

  # only required ones defined: defaults in the last column
  OUT="$(
    XX_BIN="${BIN}" NODE_OPTIONS="--no-warnings" TMPDIR="/from/tmpdir" \
      "${SHELL_BIN}" -c "unset XX_NODE_OPTIONS XX_INIT_CONFIG XX_CONFIRM XX_TMP; set -u; source \"${XXSH}\" --env; echo \"code=\${?}\"" 2>&1
  )"
  assert_contains "${OUT}" "code=0" "${SHELL_BIN}: exit code, defaults"
  assert_eq "$(row "${OUT}" XX_NODE_OPTIONS)" 'XX_NODE_OPTIONS | not defined | ${NODE_OPTIONS} | >--no-warnings< (taken from ${NODE_OPTIONS})' "${SHELL_BIN}: XX_NODE_OPTIONS not defined"
  assert_eq "$(row "${OUT}" XX_INIT_CONFIG)" "XX_INIT_CONFIG | not defined | https://stopsopa.github.io/xx/init.json | >https://stopsopa.github.io/xx/init.json<" "${SHELL_BIN}: XX_INIT_CONFIG default"
  assert_eq "$(row "${OUT}" XX_CONFIRM)" 'XX_CONFIRM | not defined | true | true (ask, unless the command has confirm: false)' "${SHELL_BIN}: XX_CONFIRM default"
  assert_eq "$(row "${OUT}" XX_TMP)" "XX_TMP | not defined | \${TMPDIR}, then /tmp | >/from/tmpdir< (scripts in >/from/tmpdir/xx-${UID_NOW}<)" "${SHELL_BIN}: XX_TMP default"

  # node is wrong: table is still printed, the reason under it
  OUT="$(XX_BIN="${BIN}" XX_NODE_BINARY="~/nowhere/node" "${SHELL_BIN}" -c "source \"${XXSH}\" --env; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: exit code, wrong node"
  assert_eq "$(row "${OUT}" XX_NODE_BINARY)" "XX_NODE_BINARY | >~/nowhere/node< | none, required | >${HOME}/nowhere/node< (not usable, see below)" "${SHELL_BIN}: wrong XX_NODE_BINARY"
  assert_contains "${OUT}" "file doesn't exist" "${SHELL_BIN}: reason why node is not usable"

  # the binary is wrong: no table, error of xx.sh and raw values
  OUT="$(XX_BIN="~/nowhere/xx" XX_TMP="/some tmp" "${SHELL_BIN}" -c "unset XX_CONFIRM; set -u; source \"${XXSH}\" --env; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: exit code, wrong XX_BIN"
  assert_contains "${OUT}" "xx.sh error: XX_BIN=" "${SHELL_BIN}: error about XX_BIN"
  assert_contains "${OUT}" "XX_BIN >~/nowhere/xx<
XX_INIT_CONFIG ><
XX_CONFIRM ><
XX_TMP >/some tmp<" "${SHELL_BIN}: raw values when the binary can't be used"

  # only when it is the only argument, otherwise it is a name of a command like any other
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" --env arg; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "$(printf 'executed-env arg\ncode=0')" "${SHELL_BIN}: --env with more arguments"
done

echo "  xx --env"
XX_NODE_BINARY="~/node" XX_BIN="~/.xx/xx-bin" /bin/bash -c "source \"${XXSH}\" --env" 2>&1 | sed "s|${WORK}|<tmp>|g; s|^|    |"
exit 0
