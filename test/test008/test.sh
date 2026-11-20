DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  args: { command: `echo "count=\${#} 1=>\${1}< 2=>\${2}< 3=>\${3}<"; exit 54`, confirm: false },
  srcargs: { command: `echo "count=\${#} 1=>\${1}< 2=>\${2}< 3=>\${3}<"; return 53`, confirm: false, source: true },
});
EEE

for SHELL_BIN in /bin/bash zsh; do
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" args one 'two words' ''; echo \"code=\${?}\"")"
  assert_eq "${OUT}" "$(printf 'count=3 1=>one< 2=>two words< 3=><\ncode=54')" "${SHELL_BIN}: args"

  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" srcargs one 'two words' ''; echo \"code=\${?}\"")"
  assert_eq "${OUT}" "$(printf 'count=3 1=>one< 2=>two words< 3=><\ncode=53')" "${SHELL_BIN}: args with source: true"

  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" args; echo \"code=\${?}\"")"
  assert_eq "${OUT}" "$(printf 'count=0 1=>< 2=>< 3=><\ncode=54')" "${SHELL_BIN}: no args"
done

echo "  source xx.sh args one 'two words' ''"
exit 0
