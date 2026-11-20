DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  slow: {
    command: `
set -e
echo slow-started
sleep 30
echo slow-finished
`,
    confirm: false,
    source: true,
  },
  second: { command: `echo picked-second`, confirm: false },
});
EEE

# Every shell gets its own pseudo terminal, all of them run at the same time
# start <label> <bash|zsh> <path to shell binary>
LABELS=()
start() {
  LABELS+=("${1}")
  python3 "${DIR}/terminal.py" "${2}" "${3}" "${XXSH}" > "${WORK}/${1}.out" &
}

# check <label>
check() {
  local LABEL="${1}"
  local OUT
  OUT="$(cat "${WORK}/${LABEL}.out")"

  assert_contains "${OUT}" "slow-started" "${LABEL}: sourced script started"
  assert_not_contains "${OUT}" "slow-finished" "${LABEL}: Ctrl+C stops sourced script"
  assert_contains "${OUT}" "ALIVE1" "${LABEL}: shell is alive after Ctrl+C in sourced script and failing command after it"

  local OPTS="${OUT##*OPTS=}"
  OPTS="${OPTS%%[^a-zA-Z0-9]*}"
  if [[ -z "${OPTS}" || "${OPTS}" == *e* ]]; then
    fail "${LABEL}: 'set -e' of the script leaked to the shell, shell options >${OPTS}<"
  fi

  assert_contains "${OUT}" "picked-second" "${LABEL}: arrow down and Enter in real terminal"
  assert_contains "${OUT}" "CODE=130" "${LABEL}: Ctrl+C in the menu returns 130"
  assert_contains "${OUT}" "ALIVE2" "${LABEL}: shell is alive after Ctrl+C in the menu"
  assert_contains "${OUT##*navigate}" $'\033[?25h' "${LABEL}: cursor restored after the menu"
}

start "bash-system" bash /bin/bash

# macOS: /bin/bash is 3.2, check modern bash too if installed
for MODERN_BASH in /opt/homebrew/bin/bash /usr/local/bin/bash; do
  if [[ -x "${MODERN_BASH}" ]]; then
    start "bash-$(basename "$(dirname "$(dirname "${MODERN_BASH}")")")" bash "${MODERN_BASH}"
  fi
done

start "zsh" zsh "$(command -v zsh)"

wait

for LABEL in "${LABELS[@]}"; do
  check "${LABEL}"
done

echo "  python3 test/test018/terminal.py zsh \"\$(command -v zsh)\" xx.sh   (shells checked: ${LABELS[*]})"
exit 0
