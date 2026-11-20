DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# xx --env: values of all env vars used by xx, printed by xx.sh itself

echo 'module.exports = () => ({ "--env": { command: `echo executed-env "\${@}"`, confirm: false } });' > xx.cjs

for SHELL_BIN in /bin/bash zsh; do
  OUT="$(
    XX_NODE_BINARY="~/node" XX_NODE_OPTIONS="" XX_BIN="~/.xx/xx-bin" XX_CONFIRM="false" XX_TMP="/some tmp" \
      "${SHELL_BIN}" -c "unset XX_INIT_CONFIG; source \"${XXSH}\" --env; echo \"code=\${?}\"" 2>&1
  )"
  assert_eq "${OUT}" "XX_NODE_BINARY >~/node<
XX_NODE_OPTIONS ><
XX_BIN >~/.xx/xx-bin<
XX_INIT_CONFIG ><
XX_CONFIRM >false<
XX_TMP >/some tmp<
code=0" "${SHELL_BIN}: --env, works even though XX_BIN and XX_NODE_BINARY point nowhere"

  # nothing defined at all, also with set -u
  OUT="$(
    "${SHELL_BIN}" -c "unset XX_NODE_BINARY XX_NODE_OPTIONS XX_BIN XX_INIT_CONFIG XX_CONFIRM XX_TMP; set -u; source \"${XXSH}\" --env; echo \"code=\${?}\"" 2>&1
  )"
  assert_eq "${OUT}" "XX_NODE_BINARY ><
XX_NODE_OPTIONS ><
XX_BIN ><
XX_INIT_CONFIG ><
XX_CONFIRM ><
XX_TMP ><
code=0" "${SHELL_BIN}: --env, nothing defined"

  # only when it is the only argument, otherwise it is a name of a command like any other
  OUT="$("${SHELL_BIN}" -c "source \"${XXSH}\" --env arg; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "$(printf 'executed-env arg\ncode=0')" "${SHELL_BIN}: --env with more arguments"
done
