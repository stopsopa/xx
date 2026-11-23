DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  one: { command: `echo one \${1}`, confirm: false },
  two: { command: `echo two \${1}`, confirm: false },
  three: { command: `echo three \${1}`, confirm: false },
  "docker up": { command: `echo docker \${1}`, confirm: false },
});
EEE

# pick <keys> - prints content of script generated after pressing given keys
pick() {
  cat "$(XX_TEST_KEYS="${1}" "${BIN}" 2>/dev/null)"
}

assert_eq "$(pick "enter")" 'echo one ${1}' "enter picks first row"
assert_eq "$(pick "down,down,enter")" 'echo three ${1}' "down, down, enter"
assert_eq "$(pick "up,enter")" 'echo docker ${1}' "up from the first row wraps to the last"
assert_eq "$(pick "end,down,enter")" 'echo one ${1}' "down from the last row wraps to the first"
assert_eq "$(pick "end,home,down,enter")" 'echo two ${1}' "end, home, down"
assert_eq "$(pick "dock,enter")" 'echo docker ${1}' "typing filters by name"
assert_eq "$(pick "THR,enter")" 'echo three ${1}' "filter is case insensitive"
assert_eq "$(pick "3,enter")" 'echo three ${1}' "typing number finds row with that number"
assert_eq "$(pick "x,backspace,down,enter")" 'echo two ${1}' "backspace removes filter"

XX_TEST_KEYS="zzz,esc,enter" "${BIN}" > /dev/null 2>&1
assert_eq "${?}" "130" "esc cancels also when a filter is typed in"

XX_TEST_KEYS="zzz,enter,enter" "${BIN}" > /dev/null 2>&1
assert_eq "${?}" "130" "enter does nothing when filter matches no row"

OUT="$(XX_TEST_KEYS="down,enter" /bin/bash -c "source \"${XXSH}\" -- ARG" 2>/dev/null)"
assert_eq "${OUT}" "two ARG" "xx -- ARG passes args to command picked from the menu"

echo "  XX_TEST_KEYS=down,down,enter xx"
exit 0
