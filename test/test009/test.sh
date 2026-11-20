DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
// config trying to read stdin must not steal it from the script
try { require("fs").readFileSync(0); } catch (e) {}
module.exports = () => ({
  upper: { command: `tr a-z A-Z`, confirm: false },
  srcread: { command: `IFS= read -r XX_LINE; echo "line=\${XX_LINE}"`, confirm: false, source: true },
});
EEE

printf 'first\nsecond\n' > input.txt

for SHELL_BIN in /bin/bash zsh; do
  OUT="$(printf 'first\nsecond\n' | "${SHELL_BIN}" -c "source \"${XXSH}\" upper")"
  assert_eq "${OUT}" "$(printf 'FIRST\nSECOND')" "${SHELL_BIN}: pipe"

  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" upper < input.txt")"
  assert_eq "${OUT}" "$(printf 'FIRST\nSECOND')" "${SHELL_BIN}: redirection"

  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" srcread < input.txt; echo \"still=\${XX_LINE}\"")"
  assert_eq "${OUT}" "$(printf 'line=first\nstill=first')" "${SHELL_BIN}: source: true"

  OUT="$(printf 'first\n' | XX_TEST_KEYS="enter" "${SHELL_BIN}" -c "source \"${XXSH}\"" 2>/dev/null)"
  assert_eq "${OUT}" "FIRST" "${SHELL_BIN}: command picked from the menu"
done

echo "  printf 'first\\nsecond\\n' | source xx.sh upper"
exit 0
