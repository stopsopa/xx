
# xx - menu of shell commands defined in xx.ts (or xx.js, xx.mjs, xx.cjs)
# https://github.com/stopsopa/xx
#
# This file has to be SOURCED, not executed, register it as an alias in ~/.bashrc or ~/.zshrc:
#
#   export XX_BIN="/path/to/xx-bin"
#   export XX_NODE_BINARY="/path/to/node"
#   alias xx='source "/path/to/xx.sh"'
#
# Usage:
#   xx                         open the menu
#   xx <name|number> [args]    run command directly, args are passed to its script
#   xx -- [args]               open the menu and pass args to script of selected command
#   echo data | xx <name>      stdin is passed to the script
#   xx --help                  the rest of the options
#
# Why it is sourced: command with "source: true" in the config has to be executed in the current
# shell (e.g. "source venv/bin/activate"), and only the shell itself can do that. So the work is split:
#
#   xx binary (rust) - finds the config, shows the menu, writes script of selected command to a file,
#                      prints path of the file on stdout and says through exit code what to do with it:
#                          0   run it with /bin/bash
#                          55  source it in the current shell
#                          10  generated, but user said "no" to "Run command?"
#                          130 cancelled
#                          any other - error (already printed by the binary)
#   this file        - executes the file
#
# Contract between this file and the binary, checked on every call (__xx_check_bin):
#   1. XX_BIN is required: path to the binary. Nothing is searched or guessed.
#   2. handshake: "${XX_BIN} --handshake" has to print exactly: xx-handshake:1:<version of the binary>
#      anything else means XX_BIN points to some other program
#   3. <version of the binary> has to be equal to __XX_VERSION of this file,
#      both files come from the same github release
#
# Because the file is sourced, it never calls "exit" (that would close your terminal), only "return",
# and everything is wrapped in functions with local variables to not pollute the shell.

# Version of this file. "dev" in the repository (binary built by compile.sh is "dev" too),
# release workflow replaces it with the tag before the file is attached to the release.
__XX_VERSION="dev"

# returns 0 if XX_BIN is the xx binary of the same version as this file, otherwise explains and returns 1
__xx_check_bin() {
  if [[ -z "${XX_BIN}" ]]; then
    cat <<EEE >&2

xx.sh error: env var XX_BIN is not defined

  It has to contain path to the xx binary (the file downloaded together with xx.sh from
  https://github.com/stopsopa/xx/releases), add to ~/.bashrc or ~/.zshrc, e.g.:

    export XX_BIN="\${HOME}/.xx/xx-bin"

EEE
    return 1
  fi

  if [[ ! -f "${XX_BIN}" ]]; then
    cat <<EEE >&2

xx.sh error: XX_BIN=>${XX_BIN}< - file doesn't exist

  download the xx binary from https://github.com/stopsopa/xx/releases (version ${__XX_VERSION})
  or fix the path in XX_BIN

EEE
    return 1
  fi

  if [[ ! -x "${XX_BIN}" ]]; then
    cat <<EEE >&2

xx.sh error: XX_BIN=>${XX_BIN}< - file is not executable, run:

    chmod a+x "${XX_BIN}"

EEE
    return 1
  fi

  local __XX_EXPECTED="xx-handshake:1:"
  local __XX_ANSWER
  __XX_ANSWER="$("${XX_BIN}" --handshake < /dev/null 2> /dev/null)"

  if [[ "${__XX_ANSWER}" != "${__XX_EXPECTED}"* ]]; then
    cat <<EEE >&2

xx.sh error: XX_BIN=>${XX_BIN}< - it is not the xx binary

  "${XX_BIN} --handshake"
  was expected to print >${__XX_EXPECTED}<version>< but it printed >${__XX_ANSWER}<

  download the xx binary from https://github.com/stopsopa/xx/releases (version ${__XX_VERSION})
  or fix the path in XX_BIN

EEE
    return 1
  fi

  local __XX_BIN_VERSION="${__XX_ANSWER#"${__XX_EXPECTED}"}"

  if [[ "${__XX_BIN_VERSION}" != "${__XX_VERSION}" ]]; then
    cat <<EEE >&2

xx.sh error: versions of xx.sh and of the xx binary are different, they have to be from the same release

  xx.sh     : ${__XX_VERSION}
  xx binary : ${__XX_BIN_VERSION}   (XX_BIN=>${XX_BIN}<)

  download both files of the same version from https://github.com/stopsopa/xx/releases

EEE
    return 1
  fi

  return 0
}

# Used only in bash, see __xx_source below.
# Switches off everything what __xx_source switched on.
__xx_guard_off() {
  trap - DEBUG
  set +e
  if [[ "${__XX_FLAGS}" != *T* ]]; then
    set +T
  fi
  if [[ "${__XX_FLAGS}" != *E* ]]; then
    set +E
  fi
  eval "${__XX_EXTDEBUG}"
}

# Used only in bash, see __xx_source below.
# Called by bash before every single command of the sourced script (DEBUG trap).
#   ${1} - exit code of the previous command
#   ${2} - how deep in functions / sourced files the command about to run is
__xx_guard() {
  # whatever the script did with "set -e", it is off again before next command runs
  set +e

  # we are back at the prompt without passing through the cleanup in __xx_source:
  # bash 5 jumps straight to the prompt on Ctrl+C. Clean up now.
  if [[ "${2}" -lt "${__XX_DEPTH}" ]]; then
    __xx_guard_off
    return 0
  fi

  # 130 = previous command was killed by Ctrl+C
  if [[ "${1}" = "130" ]]; then
    __XX_INT="1"
  fi

  # 2 = (with extdebug) don't run the command and return from current function / sourced file,
  # repeated for every level until we are out of the sourced script
  if [[ -n "${__XX_INT}" && "${2}" -gt "${__XX_DEPTH}" ]]; then
    return 2
  fi

  return 0
}

# Sources generated script in the current shell (source: true).
#
# Protects the terminal from being closed by Ctrl+C. The problem:
# sourced script contains "set -e", Ctrl+C kills the command the script was waiting for,
# that counts as failed command and "set -e" closes the whole shell = your terminal.
# Even without Ctrl+C: any failing command after "set -e" in sourced script closes the terminal.
#
# So for scripts with source: true "set -e" is neutralised - script continues after failed command.
# Ctrl+C stops the script and gives control back to the prompt, with return code 130.
#
# How (each shell needs different trick, all found by experiments, covered by test/test018):
#   zsh  - "if source ...; then" - zsh ignores "set -e" in everything executed as a condition,
#          options are local to this function (reverted on return), Ctrl+C returns from the function
#   bash - "if source" trick doesn't work in bash 3.2 (macOS), and trap on INT is not reliable,
#          so DEBUG trap (__xx_guard) is executed before every command of the script:
#          it switches "set -e" off again and stops the script after Ctrl+C
#
# WARNING: "exit" inside of a script with source: true closes the terminal, nothing can be done
# about it from here - use "return" in such scripts.
__xx_source() {
  local __XX_FILE="${1}"
  shift

  if [ -n "${ZSH_VERSION}" ]; then
    setopt localoptions localtraps
    trap 'return 130' INT
    local __XX_ZCODE="0"
    if source "${__XX_FILE}" "${@}"; then
      __XX_ZCODE="0"
    else
      __XX_ZCODE="${?}"
    fi
    # must be off before "return" with non zero code, otherwise that return closes the shell
    set +e
    return "${__XX_ZCODE}"
  fi

  # not local: __xx_guard needs them also when bash jumped out of this function on Ctrl+C
  __XX_DEPTH="${#FUNCNAME[@]}"
  __XX_FLAGS="${-}"
  __XX_EXTDEBUG="$(shopt -p extdebug)"
  __XX_INT=""

  # -T: DEBUG trap works also inside of sourced files and functions
  set -T
  # extdebug: DEBUG trap can stop the script by returning 2
  shopt -s extdebug
  trap '__xx_guard "${?}" "${#FUNCNAME[@]}"' DEBUG

  source "${__XX_FILE}" "${@}"

  local __XX_CODE="${?}"

  __xx_guard_off

  if [[ -n "${__XX_INT}" ]]; then
    __XX_CODE="130"
  fi

  return "${__XX_CODE}"
}

__xx_main() {
  # version of this file is printed even when the binary is missing or broken,
  # version of the binary follows after it passed the check
  if [[ "${1}" = "--version" || "${1}" = "-V" ]]; then
    echo "xx.sh ${__XX_VERSION}"
  fi

  __xx_check_bin || return 1

  # these only print something, nothing to execute afterwards
  case "${1}" in
    --help|-h|--version|-V|--list|--init|--esm|--gen)
      "${XX_BIN}" "${@}" < /dev/null
      return "${?}"
      ;;
  esac

  # stdin is not given to the binary, it is kept untouched for the final script.
  # The menu doesn't need it, it talks to /dev/tty directly.
  local __XX_GENERATED
  local __XX_CODE
  __XX_GENERATED="$("${XX_BIN}" "${@}" < /dev/null)"
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
