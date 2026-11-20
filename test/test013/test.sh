DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# check <content of xx.cjs> <expected fragment of error>
check() {
  echo "${1}" > xx.cjs
  OUT="$("${BIN}" --list 2>&1)"
  assert_eq "${?}" "1" "exit code for config >${1}<"
  assert_contains "${OUT}" "${2}" "error for config >${1}<"
  assert_contains "${OUT}" "${WORK}/project/xx.cjs" "path of config in error for >${1}<"
}

check 'module.exports = { a: { command: `echo` } };' "default export is not a function"
check 'module.exports = () => "string";' "object is not returned"
check 'module.exports = () => ({ bad: "string" });' "value for key >bad<"
check 'module.exports = () => ({ bad: { command: 5 } });' "value.command for key >bad<"
check 'module.exports = () => ({ bad: { description: "no command" } });' "value.command for key >bad<"
check 'module.exports = () => ({' "SyntaxError"
check 'module.exports = () => ({});' "no commands defined"

echo 'module.exports = () => ({ good: { command: `echo`, confirm: false } });' > xx.cjs
OUT="$("${BIN}" missing 2>&1)"
assert_eq "${?}" "1" "exit code for unknown command"
assert_contains "${OUT}" "function >missing< not defined" "error for unknown command"

OUT="$(/bin/bash -c "source \"${XXSH}\" missing; echo \"code=\${?}\"" 2>/dev/null)"
assert_eq "${OUT}" "code=1" "wrapper return code for unknown command"

echo "  xx --list   (with broken xx.cjs)"
exit 0
