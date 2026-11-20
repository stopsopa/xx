DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir sub
cat <<'EEE' > xx.cjs
module.exports = () => ({
  src: { command: `export XX_T6="from-source"; cd sub`, confirm: false, source: true },
  nosrc: { command: `export XX_T6="from-bash"; cd sub`, confirm: false },
  failing: { command: `return 7`, confirm: false, source: true },
  sete: { command: `set -e; false; export XX_T6="after-false"`, confirm: false, source: true },
});
EEE

"${BIN}" src > /dev/null
assert_eq "${?}" "55" "exit code of binary for source: true"

for SHELL_BIN in /bin/bash zsh; do
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" src; echo \"\${XX_T6}|\$(basename \"\$(pwd)\")\"")"
  assert_eq "${OUT}" "from-source|sub" "${SHELL_BIN}: source: true changes current shell"

  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" nosrc; echo \"\${XX_T6}|\$(basename \"\$(pwd)\")\"")"
  assert_eq "${OUT}" "|project" "${SHELL_BIN}: without source current shell is untouched"

  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" failing; echo \"code=\${?}\"")"
  assert_eq "${OUT}" "code=7" "${SHELL_BIN}: return code of sourced script"

  # "set -e" in sourced script would close the terminal on first failing command, so it is neutralised
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" sete; echo \"\${XX_T6}\"; false; echo still-here")"
  assert_eq "${OUT}" "$(printf 'after-false\nstill-here')" "${SHELL_BIN}: set -e of sourced script doesn't close or infect the shell"
done

echo "  source xx.sh src   (bash and zsh)"
exit 0
