DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir .git

check_config .git/xx.ts ts ".git/xx.ts"
check_config .git/xx.js esm ".git/xx.js (es module)"
check_config .git/xx.js cjs ".git/xx.js (commonjs)"
check_config .git/xx.mjs esm ".git/xx.mjs"
check_config .git/xx.cjs cjs ".git/xx.cjs"

assert_eq "$(ls -A)" ".git" "nothing was created in pwd"

echo "  xx <name>   (config in .git/xx.ts, .git/xx.js, .git/xx.mjs, .git/xx.cjs)"
exit 0
