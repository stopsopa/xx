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

echo "  xx --list   (in different combinations of .git/xx.cjs ./xx.cjs ~/xx.cjs)"
exit 0
