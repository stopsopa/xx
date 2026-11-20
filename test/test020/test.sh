DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# without .git
check_config xx.ts ts "./xx.ts"
check_config xx.js esm "./xx.js (es module)"
check_config xx.js cjs "./xx.js (commonjs)"
check_config xx.mjs esm "./xx.mjs"
check_config xx.cjs cjs "./xx.cjs"

# with empty .git next to it
mkdir .git

check_config xx.ts ts "./xx.ts with .git"
check_config xx.js esm "./xx.js (es module) with .git"
check_config xx.js cjs "./xx.js (commonjs) with .git"
check_config xx.mjs esm "./xx.mjs with .git"
check_config xx.cjs cjs "./xx.cjs with .git"

# nothing anywhere: error lists what was looked for and where
OUT="$("${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "exit code when there is no config"
assert_contains "${OUT}" "looked for xx.ts, xx.js, xx.mjs, xx.cjs in:" "error when there is no config"
assert_contains "${OUT}" "${WORK}/project/.git" "error lists .git"
assert_contains "${OUT}" "${WORK}/home" "error lists home"

echo "  xx <name>   (config in ./xx.ts, ./xx.js, ./xx.mjs, ./xx.cjs)"
exit 0
