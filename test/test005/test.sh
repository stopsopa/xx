DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  a: { command: `echo a`, confirm: false },
  last: { command: `echo last`, confirm: false, order: 1001 },
  b: { command: `echo b`, confirm: false },
  first: { command: `echo first`, confirm: false, order: -1 },
  "1": { command: `echo named-one`, confirm: false, order: 5 },
});
EEE

EXPECTED="$(printf '  1 - first\n  2 - a\n  3 - b\n  4 - 1\n  5 - last')"
assert_eq "$("${BIN}" --list)" "${EXPECTED}" "order in --list"

assert_eq "$(cat "$("${BIN}" 1)")" "echo first" "xx 1 picks first row of the menu, not command named 1"
assert_eq "$(cat "$("${BIN}" 5)")" "echo last" "xx 5"
assert_eq "$(cat "$("${BIN}" b)")" "echo b" "xx b"

"${BIN}" 6 > /dev/null 2>&1
assert_eq "${?}" "1" "exit code for number out of range"

echo "  xx 1"
exit 0
