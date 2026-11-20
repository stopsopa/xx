DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir .git
GEN="${WORK}/project/.git/xx_generated.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  ask: { command: `echo ask` },
  asktrue: { command: `echo asktrue`, confirm: true },
  noask: { command: `echo noask`, confirm: false },
});
EEE

OUT="$(XX_TEST_KEYS="n" "${BIN}" ask 2>"${WORK}/err")"
assert_eq "${?}" "10" "exit code after answering no"
assert_eq "$(cat "${GEN}")" "echo ask" "script is written even when not confirmed"
assert_contains "$(cat "${WORK}/err")" "Run command?" "question is shown"

XX_TEST_KEYS="y" "${BIN}" ask > /dev/null 2>&1
assert_eq "${?}" "0" "exit code after answering y"

XX_TEST_KEYS="enter" "${BIN}" asktrue > /dev/null 2>&1
assert_eq "${?}" "0" "exit code after Enter (default is yes)"

XX_TEST_KEYS="ctrlc" "${BIN}" ask > /dev/null 2>&1
assert_eq "${?}" "130" "exit code after Ctrl+C on the question"

ERR="$(XX_CONFIRM=false XX_TEST_KEYS="n" "${BIN}" ask 2>&1 > /dev/null)"
assert_eq "${?}" "0" "exit code with XX_CONFIRM=false"
assert_not_contains "${ERR}" "Run command?" "no question with XX_CONFIRM=false"

# the old name XXCONFIRM is not recognised anymore
ERR="$(XXCONFIRM=false XX_TEST_KEYS="n" "${BIN}" ask 2>&1 > /dev/null)"
assert_eq "${?}" "10" "exit code with the old XXCONFIRM=false"
assert_contains "${ERR}" "Run command?" "question is asked with the old XXCONFIRM=false"

ERR="$(XX_TEST_KEYS="n" "${BIN}" noask 2>&1 > /dev/null)"
assert_eq "${?}" "0" "exit code with confirm: false"
assert_not_contains "${ERR}" "Run command?" "no question with confirm: false"

# through the wrapper: not confirmed script is not executed
OUT="$(XX_TEST_KEYS="n" /bin/bash -c "source \"${XXSH}\" ask; echo \"code=\${?}\"" 2>/dev/null)"
assert_contains "${OUT}" "no confirmation to execute" "wrapper info"
assert_contains "${OUT}" "code=10" "wrapper return code"
assert_not_contains "${OUT}" "$(printf '\nask\n')" "script was not executed"

echo "  XX_TEST_KEYS=n xx ask"
exit 0
