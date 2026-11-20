DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# --init would work: templates are local
echo "{\"ts\": \"${ROOT}/templates/xx.ts\"}" > "${WORK}/init.json"
export XX_INIT_CONFIG="${WORK}/init.json"

# break the contract: md5 embedded in the wrapper is changed to another valid looking hash
BROKEN_MD5="00000000000000000000000000000000"
sed "s/^__XX_BIN_MD5=\".*\"\$/__XX_BIN_MD5=\"${BROKEN_MD5}\"/" "${XXSH}" > "${WORK}/xx-broken.sh"
grep -q -x -F "__XX_BIN_MD5=\"${BROKEN_MD5}\"" "${WORK}/xx-broken.sh" || fail "md5 was not changed in the copy of the wrapper"

if cmp -s "${XXSH}" "${WORK}/xx-broken.sh"; then
  fail "copy of the wrapper is identical with the original"
fi

for SHELL_BIN in /bin/bash zsh; do
  OUT="$("${SHELL_BIN}" -c "source \"${WORK}/xx-broken.sh\" --init; echo \"code=\${?}\"" 2>&1)"

  assert_contains "${OUT}" "xx.sh error: XX_BIN=>${BIN}< - it is not the xx binary this xx.sh was built with" "${SHELL_BIN}: error"
  assert_contains "${OUT}" "md5 xx.sh expects    : ${BROKEN_MD5}" "${SHELL_BIN}: md5 from the wrapper"
  assert_contains "${OUT}" "version of xx.sh     : dev" "${SHELL_BIN}: version of the wrapper"
  assert_contains "${OUT}" ": xx dev" "${SHELL_BIN}: version of the binary"
  assert_contains "${OUT}" "come from different versions" "${SHELL_BIN}: suggestion"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: return code"

  # the binary was never asked to do --init
  assert_eq "$(ls -A)" "" "${SHELL_BIN}: nothing was created in the directory"
done

# the same directory, the same command, the wrapper which was not tampered with: works
OUT="$(/bin/bash -c "source \"${XXSH}\" --init; echo \"code=\${?}\"" 2>&1)"
assert_contains "${OUT}" "code=0" "untouched wrapper: return code"
cmp -s xx.ts "${ROOT}/templates/xx.ts" || fail "untouched wrapper: xx.ts was not created"

# this is how the broken contract looks like for the user
echo "  source xx-broken.sh --init   (md5 in xx.sh changed), what the user sees:"
"${SHELL_BIN}" -c "source \"${WORK}/xx-broken.sh\" --init" 2>&1 | sed "s|${WORK}|<tmp>|g; s|${ROOT}|<repo>|g; s|^|    |"
exit 0
