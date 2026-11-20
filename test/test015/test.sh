DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir .git
GEN="${WORK}/project/.git/xx_generated.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  one: { command: `echo executed > executed.txt` },
  two: { command: `echo two > executed.txt` },
});
EEE

OUT="$("${BIN}" --gen one 2>&1)"
assert_eq "${?}" "0" "exit code of --gen one"
assert_contains "${OUT}" "script generated >${GEN}<" "info"
assert_contains "${OUT}" "echo executed > executed.txt" "content is printed"
assert_eq "$(cat "${GEN}")" "echo executed > executed.txt" "script is written"

OUT="$(/bin/bash -c "source \"${XXSH}\" --gen 2; echo \"code=\${?}\"" 2>&1)"
assert_contains "${OUT}" "echo two > executed.txt" "--gen 2 through wrapper"
assert_contains "${OUT}" "code=0" "wrapper return code"

OUT="$(XX_TEST_KEYS="down,enter" "${BIN}" --gen 2>/dev/null)"
assert_contains "${OUT}" "echo two > executed.txt" "--gen with the menu"

if [[ -f executed.txt ]]; then
  fail "--gen executed the script"
fi

echo "  xx --gen one"
exit 0
