DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

OUT="$("${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "exit code when no config exists"
assert_contains "${OUT}" "looked for xx.ts, xx.js, xx.mjs, xx.cjs in:" "error lists file names"
assert_contains "${OUT}" "  ${WORK}/project" "error lists pwd"
assert_contains "${OUT}" "  ${WORK}/home" "error lists home"

echo 'module.exports = () => ({ fromhome: { command: `echo` } });' > "${HOME}/xx.cjs"
assert_eq "$("${BIN}" --list)" "  1 - fromhome" "~/xx.cjs used when nothing else exists"

echo 'module.exports = () => ({ fromlocal: { command: `echo` } });' > xx.cjs
assert_eq "$("${BIN}" --list)" "  1 - fromlocal" "./xx.cjs wins over ~/xx.cjs"

mkdir .git
assert_eq "$("${BIN}" --list)" "  1 - fromlocal" "./xx.cjs still used when .git has no xx.cjs"

echo 'module.exports = () => ({ fromgit: { command: `echo` } });' > .git/xx.cjs
assert_eq "$("${BIN}" --list)" "  1 - fromgit" ".git/xx.cjs wins over ./xx.cjs"

# mistyped option of xx is taken for a name of a command, the error gives a hint
OUT="$("${BIN}" --verion 2>&1)"
assert_eq "${?}" "1" "mistyped option: exit code"
assert_contains "${OUT}" "function >--verion< not defined in" "mistyped option: the error as before"
assert_contains "${OUT}" "did you mean: xx --version" "mistyped option: hint"
assert_contains "$("${BIN}" --something-else 2>&1)" "there is no such option, see: xx --help" "unknown option: hint"
assert_not_contains "$("${BIN}" nosuchcommand 2>&1)" "option" "unknown command: no hint about options"

echo "  xx --list   (in different combinations of .git/xx.cjs ./xx.cjs ~/xx.cjs)"
exit 0
