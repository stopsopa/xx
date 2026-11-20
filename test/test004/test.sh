DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir .git
GEN="${WORK}/project/.git/xx_generated.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  hello: {
    command: `
set -e
echo "name is <% name %>" > executed.txt
echo \${1}
`,
    confirm: false,
  },
});
EEE

OUT="$("${BIN}" hello)"
assert_eq "${?}" "0" "exit code"
assert_eq "${OUT}" "${GEN}" "stdout is path of generated script"

EXPECTED='
set -e
echo "name is hello" > executed.txt
echo ${1}
'
assert_eq "$(cat "${OUT}"; echo x)" "${EXPECTED}x" "content of generated script"

if [[ -f executed.txt ]]; then
  fail "binary executed the script, it should only generate it"
fi

echo "  xx hello"
exit 0
