
# xx - menu of shell commands defined in xx.cjs
# https://github.com/stopsopa/xx
#
# This file has to be SOURCED, not executed, register it as an alias in ~/.bashrc or ~/.zshrc:
#
#   alias xx='source "/path/to/xx.sh"'
#
# Usage:
#   xx                         open the menu
#   xx <name|number> [args]    run command directly, args are passed to its script
#   xx -- [args]               open the menu and pass args to script of selected command
#   echo data | xx <name>      stdin is passed to the script
#   xx --help                  the rest of the options
#
# Why it is sourced: command with "source: true" in xx.cjs has to be executed in the current shell
# (e.g. "source venv/bin/activate"), and only the shell itself can do that. So the work is split:
#
#   xx binary (rust) - finds xx.cjs, shows the menu, writes script of selected command to a file,
#                      prints path of the file on stdout and says through exit code what to do with it:
#                          0   run it with /bin/bash
#                          55  source it in the current shell
#                          10  generated, but user said "no" to "Run command?"
#                          130 cancelled
#                          any other - error (already printed by the binary)
#   this file        - executes the file
#
# Where the binary is searched (first found wins):
#   ${XX_BIN}                  explicit path
#   <this dir>/xx-bin          installed from github release
#   <this dir>/bin/<arch>/xx   cloned repository after: /bin/bash compile.sh
#
# Because the file is sourced, it never calls "exit" (that would close your terminal), only "return",
# and everything is wrapped in functions with local variables to not pollute the shell.

# location of this file, in bash and in zsh
if [ -n "${ZSH_VERSION}" ]; then
  __XX_DIR="$( cd "$( dirname "${(%):-%x}" )" && pwd -P )"
else
  __XX_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
fi

# prints path to the binary, returns 1 if not found
__xx_find_bin() {
  if [[ -n "${XX_BIN}" ]]; then
    echo "${XX_BIN}"
    return 0
  fi

  if [[ -f "${__XX_DIR}/xx-bin" ]]; then
    echo "${__XX_DIR}/xx-bin"
    return 0
  fi

  local ARCH_DIR
  case "$(uname -m)" in
    arm64|aarch64) ARCH_DIR="arm64" ;;
    x86_64|amd64) ARCH_DIR="x64" ;;
    *) ARCH_DIR="$(uname -m)" ;;
  esac

  if [[ -f "${__XX_DIR}/bin/${ARCH_DIR}/xx" ]]; then
    echo "${__XX_DIR}/bin/${ARCH_DIR}/xx"
    return 0
  fi

  return 1
}

# Sources generated script in the current shell (source: true).
#
# Protects the shell from being closed by Ctrl+C:
# when sourced script contains "set -e" and Ctrl+C kills command it was waiting for,
# that command "fails" and "set -e" closes the whole terminal.
# Fix is different for each shell (both tested in test/test021):
#   zsh  - options are local to this function (set -e of the script is reverted on return),
#          Ctrl+C returns from the function
#   bash - Ctrl+C switches "set -e" off before bash checks result of the killed command
#
# WARNING: "exit" inside of a script with source: true closes the terminal, nothing can be done
# about it from here - use "return" in such scripts.
__xx_source() {
  local __XX_FILE="${1}"
  shift

  if [ -n "${ZSH_VERSION}" ]; then
    setopt localoptions localtraps
    trap 'return 130' INT
    if source "${__XX_FILE}" "${@}"; then
      return 0
    else
      return "${?}"
    fi
  fi

  local __XX_CODE
  local __XX_TRAP
  __XX_TRAP="$(trap -p INT)"
  trap 'set +e; trap - INT; eval "${__XX_TRAP}"' INT
  source "${__XX_FILE}" "${@}"
  __XX_CODE="${?}"
  set +e
  trap - INT
  eval "${__XX_TRAP}"
  return "${__XX_CODE}"
}

__xx_main() {
  # --lock, --unlock, --copy are not ported, they still live in the old xx.sh
  if [[ "${1}" = "--lock" || "${1}" = "--unlock" || "${1}" = "--copy" ]]; then
    if [[ -f "${XX_LEGACY_SH}" ]]; then
      source "${XX_LEGACY_SH}" "${@}"
      return "${?}"
    fi

    cat <<EEE

xx.sh error: ${1} is handled by the old xx.sh, point to it with env var XX_LEGACY_SH=>${XX_LEGACY_SH}<

  export XX_LEGACY_SH="/path/to/old/xx.sh"

EEE
    return 1
  fi

  local __XX_BIN
  __XX_BIN="$(__xx_find_bin)"

  if [[ -z "${__XX_BIN}" || ! -f "${__XX_BIN}" ]]; then
    cat <<EEE

xx.sh error: xx binary not found >${__XX_BIN}<, checked:
  env var XX_BIN=>${XX_BIN}<
  ${__XX_DIR}/xx-bin
  ${__XX_DIR}/bin/<arch>/xx

  download it from https://github.com/stopsopa/xx/releases
  and save as ${__XX_DIR}/xx-bin

EEE
    return 1
  fi

  # these only print something, nothing to execute afterwards
  case "${1}" in
    --help|-h|--version|-V|--list|--init|--gen)
      "${__XX_BIN}" "${@}" < /dev/null
      return "${?}"
      ;;
  esac

  # stdin is not given to the binary, it is kept untouched for the final script.
  # The menu doesn't need it, it talks to /dev/tty directly.
  local __XX_GENERATED
  local __XX_CODE
  __XX_GENERATED="$("${__XX_BIN}" "${@}" < /dev/null)"
  __XX_CODE="${?}"

  # drop the name of the command (or --), what is left are arguments for the script
  if [[ "${#}" -gt 0 ]]; then
    shift
  fi

  case "${__XX_CODE}" in
    0)
      /bin/bash "${__XX_GENERATED}" "${@}"
      return "${?}"
      ;;
    55)
      __xx_source "${__XX_GENERATED}" "${@}"
      return "${?}"
      ;;
    10)
      cat <<EEE

    xx info: generating ${__XX_GENERATED} success - no confirmation to execute

EEE
      return 10
      ;;
    *)
      return "${__XX_CODE}"
      ;;
  esac
}

__xx_main "${@}"
