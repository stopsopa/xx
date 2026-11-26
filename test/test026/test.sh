DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# --config <path> / XX_CONFIG: config pointed directly, used from any directory.
# The config and files next to it live in ${TOOLS}, xx is called in ${WORK}/project and ${WORK}/other

TOOLS="${WORK}/tools dir"
mkdir -p "${TOOLS}/xx" "${TOOLS}/.git" "${WORK}/other" "${WORK}/empty"

cat <<'EEE' > "${TOOLS}/xx/tool.sh"
echo "tool: pwd=$(pwd -P) args=${*}"
EEE

echo 'module.exports = { text: "from-shared" };' > "${TOOLS}/shared.cjs"

# any file name is allowed
cat <<'EEE' > "${TOOLS}/menu.cjs"
const shared = require("./shared.cjs");
module.exports = (setup, ctx) => ({
  ctx: {
    command: `echo "ctx: args=${ctx.args.join("+")} cwd=${ctx.cwd} configPath=${ctx.configPath} configDir=${ctx.configDir} shared=${shared.text}"`,
  },
  tool: {
    command: `/bin/bash "${ctx.configDir}/xx/tool.sh" "\${@}"`,
    description: `runs <% name %>`,
  },
  first: { command: `echo first`, order: -1 },
  ask: { command: `echo asked "\${@}"`, confirm: true },
  src: { command: `cd /; XX_SOURCED="yes-\${1}"`, source: true },
  nested: { command: `source "${process.env.XXSH_FOR_TEST}" marker`, },
  marker: { command: `echo "marker of menu.cjs"` },
});
EEE

# directory: xx.* in it, .git of the directory is not searched
echo 'export default () => ({ indir: { command: `echo indir` } });' > "${TOOLS}/xx.mjs"
echo 'module.exports = () => ({ ingit: { command: `echo ingit` } });' > "${TOOLS}/.git/xx.cjs"

echo 'module.exports = () => ({ marker: { command: `echo "marker of other.cjs"` } });' > "${TOOLS}/other.cjs"

# the normal lookup must be skipped completely
mkdir .git
echo 'module.exports = () => ({ local: { command: `echo local` }, marker: { command: `echo "marker of project"` } });' > xx.cjs
echo 'module.exports = () => ({ home: { command: `echo home` } });' > "${HOME}/xx.cjs"

CFG="${TOOLS}/menu.cjs"
PROJECT="${WORK}/project"

# ---- the binary alone -------------------------------------------------------------------------

assert_eq "$("${BIN}" --list)" "  1 - local
  2 - marker" "without --config nothing changes"

assert_eq "$("${BIN}" --config "${CFG}" --list)" "  1 - first
  2 - ctx
  3 - tool	runs tool
  4 - ask
  5 - src
  6 - nested
  7 - marker" "--config <file> --list (order, <% name %>)"

assert_eq "$("${BIN}" --config="${CFG}" --list)" "$("${BIN}" --config "${CFG}" --list)" "--config=<file>"
assert_eq "$(XX_CONFIG="${CFG}" "${BIN}" --list)" "$("${BIN}" --config "${CFG}" --list)" "XX_CONFIG"
assert_contains "$("${BIN}" --config "${CFG}" --list --json)" '"name":"tool"' "--list --json"

# relative to the current directory, ~/ means home
assert_eq "$("${BIN}" --config "../tools dir/other.cjs" --list)" "  1 - marker" "relative path"
cp "${TOOLS}/other.cjs" "${HOME}/tools.cjs"
assert_eq "$(XX_CONFIG="~/tools.cjs" "${BIN}" --list)" "  1 - marker" "~/ in XX_CONFIG"
assert_eq "$("${BIN}" --config "~/tools.cjs" --list)" "  1 - marker" "~/ in --config"

# directory
assert_eq "$("${BIN}" --config "${TOOLS}" --list)" "  1 - indir" "--config <directory>: xx.* in it, not in its .git"

# the argument wins over the env var
assert_eq "$(XX_CONFIG="${TOOLS}/other.cjs" "${BIN}" --config "${TOOLS}" --list)" "  1 - indir" "--config wins over XX_CONFIG"
# empty XX_CONFIG = not defined
assert_eq "$(XX_CONFIG="" "${BIN}" --list)" "  1 - local
  2 - marker" "empty XX_CONFIG"

# errors: absolute path in the message, no fallback to ./xx.cjs
# error <expected fragment> <label> <args...>
error() {
  local EXPECTED="${1}"
  local LABEL="${2}"
  shift 2
  local OUT
  OUT="$("${BIN}" "${@}" 2>&1)"
  assert_eq "${?}" "1" "${LABEL}: exit code"
  assert_contains "${OUT}" "${EXPECTED}" "${LABEL}"
}
error "--config: config >${PROJECT}/nothing.ts< doesn't exist" "missing file" --config nothing.ts --list
error "--config: config >${PROJECT}/nothing.ts< doesn't exist" "missing file, running a command" --config nothing.ts local
error "--config: directory >${WORK}/empty< has no config in it, looked for xx.ts, xx.js, xx.mjs, xx.cjs" "directory without config" --config ../empty --list
error "--config: config >${TOOLS}/xx/tool.sh< has unsupported extension >sh<" "unsupported extension" --config "${TOOLS}/xx/tool.sh" --list
error "--config needs a path" "--config without a path" --config
error "--config: the path is empty" "--config= without a path" --config= --list
error "function >local< not defined in >${CFG}<" "command of ./xx.cjs is not visible" --config "${CFG}" local
OUT="$(XX_CONFIG="nothing.ts" "${BIN}" --list 2>&1)"
assert_contains "${OUT}" "XX_CONFIG: config >${PROJECT}/nothing.ts< doesn't exist" "missing file from XX_CONFIG"

# errors of the config itself keep the path
echo 'module.exports = () => ({ broken: "not an object" });' > "${TOOLS}/broken.cjs"
error "${TOOLS}/broken.cjs" "broken config" --config "${TOOLS}/broken.cjs" --list

# --init / --esm
error "--config can't be used together with --init" "--init" --config "${WORK}/new.ts" --init
error "--config can't be used together with --esm" "--esm" --config "${WORK}/new.ts" --esm
[[ -e "${WORK}/new.ts" ]] && fail "--init with --config created a file"

# ctx, --gen
OUT="$("${BIN}" --config "${CFG}" --gen ctx a "b c" 2> /dev/null)"
assert_contains "${OUT}" "ctx: args=a+b c cwd=${PROJECT} configPath=${CFG} configDir=${TOOLS} shared=from-shared" "ctx with --config, relative require, --gen"
assert_not_contains "${OUT}" "args=--config" "--config is not in ctx.args"

# ctx.configDir without --config
echo 'module.exports = (setup, ctx) => ({ dir: { command: `echo "configDir=${ctx.configDir}"` } });' > "${WORK}/other/xx.cjs"
assert_contains "$(cd "${WORK}/other" && "${BIN}" --gen dir 2> /dev/null)" "configDir=${WORK}/other" "ctx.configDir without --config"

# the generated script: in tmp, not in .git of the current directory, not next to the config.
# One file per (directory, config)
A="$("${BIN}" --config "${CFG}" marker)"
B="$(cd "${WORK}/other" && "${BIN}" --config "${CFG}" marker)"
C="$("${BIN}" --config "${TOOLS}/other.cjs" marker)"
D="$("${BIN}" marker)"
[[ "${A}" == "${TMP_GEN_DIR}/"*.sh ]] || fail "generated script expected in >${TMP_GEN_DIR}< got >${A}<"
[[ "${A}" != "${B}" ]] || fail "the same config used in two directories shares the generated script >${A}<"
[[ "${A}" != "${C}" ]] || fail "two configs used in one directory share the generated script >${A}<"
assert_eq "${D}" "${PROJECT}/.git/xx_generated.sh" "without --config the script is where it always was"
assert_eq "$(cat "${A}")" 'echo "marker of menu.cjs"' "script of the first call is not overwritten by the others"
assert_eq "$(cat "${B}")" 'echo "marker of menu.cjs"' "script generated in other directory"
assert_eq "$(cat "${C}")" 'echo "marker of other.cjs"' "script of other config"
assert_eq "$(ls "${TOOLS}" | sort | tr '\n' ' ')" "broken.cjs menu.cjs other.cjs shared.cjs xx xx.mjs " "nothing is written next to the config"

# the way described for AI agents
FILE="$(XX_CONFIRM=false "${BIN}" --config "${CFG}" "ask" arg1 < /dev/null)"
assert_eq "${?}" "0" "agent way: exit code"
assert_eq "$(/bin/bash "${FILE}" arg1)" "asked arg1" "agent way: script"

# the menu: one line with the path of the config, only when it was pointed directly
FRAME="$(XX_TEST_KEYS="esc" XX_TEST_SIZE="400x20" "${BIN}" --config "${CFG}" 2>&1 > /dev/null)"
assert_contains "${FRAME}" "config: ${CFG}" "menu shows the config in use"
# narrow terminal: the beginning of the path is cut, the name of the file stays
FRAME="$(XX_TEST_KEYS="esc" XX_TEST_SIZE="40x20" "${BIN}" --config "${CFG}" 2>&1 > /dev/null)"
assert_contains "${FRAME}" "/tools dir/menu.cjs" "menu in narrow terminal keeps the end of the path"
FRAME="$(XX_TEST_KEYS="esc" "${BIN}" 2>&1 > /dev/null)"
assert_not_contains "${FRAME}" "config:" "menu without --config is unchanged"

# --env
OUT="$("${BIN}" --config "${CFG}" --env)"
assert_contains "${OUT}" ">${CFG}< (from --config, it wins)" "--env with --config"
OUT="$(XX_CONFIG="../tools dir" "${BIN}" --env)"
assert_contains "$(echo "${OUT}" | grep '^XX_CONFIG ')" ">${TOOLS}/xx.mjs<" "--env with XX_CONFIG"
assert_contains "$("${BIN}" --env | grep '^XX_CONFIG ')" "not used, the config is searched" "--env without config"
assert_contains "$("${BIN}" --help)" "alias ai='xx --config" "--help has the alias example"

# ---- through xx.sh, in bash and zsh -----------------------------------------------------------

export XXSH_FOR_TEST="${XXSH}"

for SHELL_BIN in /bin/bash zsh; do
  # xx <args as one string for the shell>
  xx() {
    "${SHELL_BIN}" -c "source \"${XXSH}\" ${1}; echo \"code=\${?}\"" 2>&1
  }

  # executed in the directory xx was called in, the script doesn't get --config
  OUT="$(cd "${WORK}/other" && xx "--config \"${CFG}\" tool restore \"two words\"")"
  assert_eq "${OUT}" "tool: pwd=${WORK}/other args=restore two words
code=0" "${SHELL_BIN}: command executed in the current directory, arguments without --config"

  OUT="$(cd "${WORK}/other" && xx "--config=\"${CFG}\" tool one")"
  assert_eq "${OUT}" "tool: pwd=${WORK}/other args=one
code=0" "${SHELL_BIN}: --config=<path>"

  OUT="$(cd "${WORK}/other" && XX_CONFIG="${CFG}" xx "tool one")"
  assert_eq "${OUT}" "tool: pwd=${WORK}/other args=one
code=0" "${SHELL_BIN}: XX_CONFIG"

  # after the name of the command everything belongs to the command
  OUT="$(xx "--config \"${CFG}\" tool --config abc --config=def")"
  assert_eq "${OUT}" "tool: pwd=${PROJECT} args=--config abc --config=def
code=0" "${SHELL_BIN}: --config after the name goes to the command"
  OUT="$("${BIN}" --config "${CFG}" --gen ctx --config abc 2> /dev/null)"
  assert_contains "${OUT}" "args=--config+abc " "${SHELL_BIN}: --config after the name is in ctx.args"

  # relative path, directory
  OUT="$(xx "--config \"../tools dir/menu.cjs\" tool x")"
  assert_eq "${OUT}" "tool: pwd=${PROJECT} args=x
code=0" "${SHELL_BIN}: relative path"
  OUT="$(xx "--config \"${TOOLS}\" indir")"
  assert_eq "${OUT}" "indir
code=0" "${SHELL_BIN}: directory"

  # info options
  assert_eq "$(xx "--config \"${TOOLS}\" --list")" "  1 - indir
code=0" "${SHELL_BIN}: --list"
  assert_contains "$(xx "--config \"${CFG}\" --gen marker")" 'echo "marker of menu.cjs"' "${SHELL_BIN}: --gen"
  assert_contains "$(xx "--config \"${CFG}\" --env")" ">${CFG}< (from --config, it wins)" "${SHELL_BIN}: --env"

  # menu, arguments after --
  OUT="$(XX_TEST_KEYS="tool,enter" xx "--config \"${CFG}\" -- a b" 2>&1 | tail -n 2)"
  assert_eq "${OUT}" "tool: pwd=${PROJECT} args=a b
code=0" "${SHELL_BIN}: menu with --config"

  # confirm: true
  OUT="$(XX_CONFIRM=false xx "--config \"${CFG}\" ask one")"
  assert_eq "${OUT}" "asked one
code=0" "${SHELL_BIN}: confirm: true with XX_CONFIRM=false"
  OUT="$(XX_TEST_KEYS="n" xx "--config \"${CFG}\" ask one")"
  assert_contains "${OUT}" "code=10" "${SHELL_BIN}: confirm: true answered no"

  # source: true - sourced in the calling shell, in the directory xx was called in
  OUT="$("${SHELL_BIN}" -c "cd \"${WORK}/other\"; source \"${XXSH}\" --config \"${CFG}\" src arg; echo \"code=\${?} sourced=\${XX_SOURCED} pwd=\$(pwd -P)\"" 2>&1)"
  assert_eq "${OUT}" "code=0 sourced=yes-arg pwd=/" "${SHELL_BIN}: source: true"

  # errors
  OUT="$(xx "--config nothing.ts tool")"
  assert_contains "${OUT}" "--config: config >${PROJECT}/nothing.ts< doesn't exist" "${SHELL_BIN}: missing file"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: missing file: exit code"
  OUT="$(xx "--config")"
  assert_contains "${OUT}" "--config needs a path" "${SHELL_BIN}: --config without a path"
  assert_contains "${OUT}" "code=1" "${SHELL_BIN}: --config without a path: exit code"

  # nested call: --config is not inherited (xx in the command finds ./xx.cjs of the project)...
  OUT="$(xx "--config \"${CFG}\" nested")"
  assert_eq "${OUT}" "marker of project
code=0" "${SHELL_BIN}: --config is not inherited by nested xx"
  # ...XX_CONFIG is, it is an env var
  OUT="$(XX_CONFIG="${CFG}" "${SHELL_BIN}" -c "export XX_CONFIG; source \"${XXSH}\" nested; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "marker of menu.cjs
code=0" "${SHELL_BIN}: XX_CONFIG is inherited by nested xx"
  # ...and nested --config overrides it
  OUT="$(XX_CONFIG="${TOOLS}/other.cjs" "${SHELL_BIN}" -c "export XX_CONFIG; source \"${XXSH}\" --config \"${CFG}\" nested; echo \"code=\${?}\"" 2>&1)"
  assert_eq "${OUT}" "marker of other.cjs
code=0" "${SHELL_BIN}: outer --config wins over XX_CONFIG, nested xx sees only XX_CONFIG"
done

echo "  xx --config <path> / XX_CONFIG"
exit 0
