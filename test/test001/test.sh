DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
module.exports = (setup) => ({
  zeta: { command: `echo z` },
  alpha: { command: `echo a`, description: `this is <% name %> command` },
  "with space": { command: `echo s`, description: `spaced` },
  ...setup,
});
EEE

OUT="$("${BIN}" --list)"
assert_eq "${?}" "0" "exit code of --list"

EXPECTED="$(printf '  1 - zeta\n  2 - alpha\tthis is alpha command\n  3 - with space\tspaced')"
assert_eq "${OUT}" "${EXPECTED}" "--list output"

JSON="$("${BIN}" --list --json)"
assert_contains "${JSON}" '"name":"with space"' "--list --json"
assert_contains "${JSON}" '"number":3' "--list --json"

echo "  xx --list"
exit 0
