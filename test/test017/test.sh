DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

echo 'module.exports = () => ({ one: { command: `echo executed-one`, confirm: false } });' > xx.cjs

assert_eq "$("${BIN}" --version)" "xx dev" "version of the binary"

# what the build embedded in the wrapper
MD5="$(md5sum "${BIN}" 2> /dev/null | cut -d ' ' -f 1)"
if [[ -z "${MD5}" ]]; then
  MD5="$(md5 -q "${BIN}")"
fi
grep -q -x -F "__XX_BIN_MD5=\"${MD5}\"" "${XXSH}" || fail "md5 >${MD5}< of the binary is not embedded in >${XXSH}<"
grep -q -x -F '__XX_VERSION="dev"' "${XXSH}" || fail "version is not embedded in >${XXSH}<"

# xx.sh in the repository must stay unbuilt: bash/embed.sh replaces exactly these two lines
grep -q -x -F '__XX_BIN_MD5=""' "${ROOT}/xx.sh" || fail "line __XX_BIN_MD5=\"\" not found in xx.sh of the repository"
grep -q -x -F '__XX_VERSION="dev"' "${ROOT}/xx.sh" || fail "line __XX_VERSION=\"dev\" not found in xx.sh of the repository"

# wrapper built for more binaries (release: one xx.sh for all platforms) accepts each of them
cp "${BIN}" "${WORK}/other-platform"
echo "pretend this is binary for other platform" >> "${WORK}/other-platform"
/bin/bash "${ROOT}/bash/embed.sh" v9.9.9 "${WORK}/xx-release.sh" "${WORK}/other-platform" "${BIN}" 2> /dev/null
assert_eq "${?}" "0" "exit code of bash/embed.sh"

# the binary changed after the wrapper was built
cp "${BIN}" "${WORK}/modified"
echo "x" >> "${WORK}/modified"

echo "data" > "${WORK}/plain"

# for XX_BIN="~/..."
mkdir "${HOME}/.xx"
cp "${BIN}" "${HOME}/.xx/xx-bin"

for SHELL_BIN in /bin/bash zsh; do
  # all good
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "$(printf 'executed-one\ncode=0')" "${SHELL_BIN}: binary the wrapper was built with"

  OUT="$("${SHELL_BIN}" -c "source \"${WORK}/xx-release.sh\" one; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "$(printf 'executed-one\ncode=0')" "${SHELL_BIN}: wrapper built for more binaries"

  # "~/" at the beginning of XX_BIN means home directory (the shell doesn't expand it inside of quotes)
  OUT="$(XX_BIN="~/.xx/xx-bin" "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "$(printf 'executed-one\ncode=0')" "${SHELL_BIN}: XX_BIN starting with ~/"

  OUT="$(XX_BIN="~/.xx/nothing" "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "XX_BIN=>${HOME}/.xx/nothing< - file doesn't exist" "${SHELL_BIN}: error shows expanded XX_BIN"

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
  OUT="$(XX_BIN="${FAKE}" "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "it is not the xx binary this xx.sh was built with" "${SHELL_BIN}: XX_BIN is other program"
  assert_contains "${OUT}" "md5 xx.sh expects    : ${MD5}" "${SHELL_BIN}: expected md5 is shown"
  assert_contains "${OUT}" ": I am something else" "${SHELL_BIN}: answer of the other program to --version is shown"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code when XX_BIN is other program"

  # real xx binary, but not the one the wrapper was built with
  OUT="$(XX_BIN="${WORK}/modified" "${SHELL_BIN}" -c "source \"${XXSH}\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "it is not the xx binary this xx.sh was built with" "${SHELL_BIN}: modified binary"
  assert_contains "${OUT}" "version of xx.sh     : dev" "${SHELL_BIN}: version of the wrapper is shown"
  assert_contains "${OUT}" ": xx dev" "${SHELL_BIN}: version of the binary is shown"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code for modified binary"
  assert_not_contains "${OUT}" "executed-one" "${SHELL_BIN}: nothing executed with modified binary"

  # xx.sh straight from the repository has no md5 embedded
  OUT="$("${SHELL_BIN}" -c "source \"${ROOT}/xx.sh\" one; echo \"code=\${?}\"" 2>&1)"
  assert_contains "${OUT}" "has no md5 of the xx binary embedded" "${SHELL_BIN}: xx.sh from the repository"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code of xx.sh from the repository"

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

echo "  source bin/<arch>/xx.sh --version"
exit 0
