DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  "~/help": { command: `echo`, description: `help from ~/xx.cjs`, confirm: false },
  xx: { command: `echo`, description: `second description`, confirm: false },
  ["long".repeat(40)]: { command: `echo`, confirm: false },
});
EEE

REVERSE=$'\033[7m'
RESET=$'\033[0m'

# last frame is everything after last "clear to the end of screen"
XX_TEST_KEYS="down" XX_TEST_SIZE="60x20" "${BIN}" > /dev/null 2> "${WORK}/frames"
FRAME="$(NODE_OPTIONS="" "${XX_NODE_BINARY}" -e '
  const all = require("fs").readFileSync(process.argv[1], "utf8").split("\x1b[J");
  process.stdout.write(all[all.length - 2].replace(/\r/g, ""));
' "${WORK}/frames")"

assert_contains "${FRAME}" "Select command to run" "header"
assert_contains "${FRAME}" "❯ ${REVERSE}▏   2 - xx${RESET}" "selected row is reversed"
assert_contains "${FRAME}" "  █   1 - ~/help" "not selected row"
assert_not_contains "${FRAME}" "${REVERSE}█" "not selected row is not reversed"
assert_contains "${FRAME}" "second description" "description of selected row"
assert_not_contains "${FRAME}" "help from ~/xx.cjs" "description of other row is not shown"
assert_contains "${FRAME}" "navigate" "help line"
assert_eq "$(echo "${FRAME}" | grep -cF "${REVERSE}")" "1" "number of reversed rows"

# width counted in characters, colors removed
LONGEST="$(NODE_OPTIONS="" "${XX_NODE_BINARY}" -e '
  const lines = process.argv[1].replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\n");
  console.log(Math.max(...lines.map((l) => [...l].length)));
' "${FRAME}")"
if [[ "${LONGEST}" -gt 59 ]]; then
  fail "row longer than terminal width: >${LONGEST}<"
fi

ERR="$(XX_TEST_KEYS="down,enter" "${BIN}" 2>&1 > /dev/null)"
assert_contains "${ERR}" "✔" "check mark after selection"
assert_contains "${ERR##*✔}" "2 - xx" "selected row after the check mark"

echo "  XX_TEST_KEYS=down XX_TEST_SIZE=60x20 xx"
exit 0
