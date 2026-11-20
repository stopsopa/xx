DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

echo 'module.exports = () => ({ one: { command: `echo executed-one`, confirm: false } });' > xx.cjs

# the binary side of the contract
assert_eq "$("${BIN}" --handshake)" "xx-handshake:1:dev" "answer of the binary"
assert_eq "$("${BIN}" --version)" "xx dev" "version of the binary"

# wrapper of another version: what the release workflow does to xx.sh
sed 's/^__XX_VERSION="dev"$/__XX_VERSION="v9.9.9"/' "${XXSH}" > "${WORK}/xx-other.sh"
grep -q '^__XX_VERSION="v9.9.9"$' "${WORK}/xx-other.sh" || fail "version line not found in xx.sh, release workflow relies on it"

# program which is not xx
printf '#!/bin/bash\necho "I am something else"\n' > "${WORK}/fake"
chmod a+x "${WORK}/fake"

echo "data" > "${WORK}/plain"

for SHELL_BIN in /bin/bash zsh; do
  # all good
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "$(printf 'executed-one\ncode=0')" "${SHELL_BIN}: matching versions"

  # XX_BIN not defined: nothing is searched
  OUT="$(unset XX_BIN; "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "env var XX_BIN is not defined" "${SHELL_BIN}: XX_BIN not defined"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code when XX_BIN not defined"
  assert_not_contains "${OUT}" "executed-one" "${SHELL_BIN}: nothing executed when XX_BIN not defined"

  # points to nothing
  OUT="$(XX_BIN="${WORK}/nothing-here" "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "XX_BIN=>${WORK}/nothing-here< - file doesn't exist" "${SHELL_BIN}: XX_BIN points to nothing"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code when XX_BIN points to nothing"

  # not executable
  OUT="$(XX_BIN="${WORK}/plain" "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "file is not executable" "${SHELL_BIN}: XX_BIN not executable"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code when XX_BIN not executable"

  # other program
  OUT="$(XX_BIN="${WORK}/fake" "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "it is not the xx binary" "${SHELL_BIN}: XX_BIN is other program"
  assert_contains "${OUT}" "it printed >I am something else<" "${SHELL_BIN}: answer of the other program is shown"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code when XX_BIN is other program"

  # versions differ
  OUT="$("${SHELL_BIN}" -c "source \"${WORK}/xx-other.sh\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "versions of xx.sh and of the xx binary are different" "${SHELL_BIN}: version mismatch"
  assert_contains "${OUT}" "xx.sh     : v9.9.9" "${SHELL_BIN}: version of the wrapper shown"
  assert_contains "${OUT}" "xx binary : dev" "${SHELL_BIN}: version of the binary shown"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code on version mismatch"
  assert_not_contains "${OUT}" "executed-one" "${SHELL_BIN}: nothing executed on version mismatch"

  # also --help is refused on mismatch
  OUT="$("${SHELL_BIN}" -c "source \"${WORK}/xx-other.sh\" --help; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: --help refused on version mismatch"

  # --version: both parts answer
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" --version; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "$(printf 'xx.sh dev\nxx dev\ncode=0')" "${SHELL_BIN}: --version"

  # --version of the wrapper is printed also when the binary is missing
  OUT="$(unset XX_BIN; "${SHELL_BIN}" -c "source \"${XXSH}\" --version; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "xx.sh dev" "${SHELL_BIN}: --version without the binary"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code of --version without the binary"

  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" --help")"
  assert_contains "${OUT}" "https://github.com/stopsopa/xx" "${SHELL_BIN}: --help"

  # options dropped from this version are not special anymore
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" --lock; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "function >--lock< not defined" "${SHELL_BIN}: --lock is not handled"
done

echo "  source xx.sh --version"
exit 0
