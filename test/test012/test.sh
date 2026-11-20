DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir .git
GEN="${WORK}/project/.git/xx_generated.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  one: { command: `echo executed-one`, confirm: false },
});
EEE

for KEYS in "esc" "ctrlc" "down" ""; do
  echo "echo stale" > "${GEN}"

  OUT="$(XX_TEST_KEYS="${KEYS}" "${BIN}" 2>/dev/null)"
  assert_eq "${?}" "130" "exit code for keys >${KEYS}<"
  assert_eq "${OUT}" "" "nothing on stdout for keys >${KEYS}<"

  if [[ -f "${GEN}" ]]; then
    fail "generated script exists after cancel, keys >${KEYS}<"
  fi
done

for SHELL_BIN in /bin/bash zsh; do
  OUT="$(XX_TEST_KEYS="esc" "${SHELL_BIN}" -c "source \"${XXSH}\"; echo \"code=\${?}\"" 2>/dev/null)"
  assert_eq "${OUT}" "code=130" "${SHELL_BIN}: wrapper after cancel"
done

echo "  XX_TEST_KEYS=esc xx"
exit 0
