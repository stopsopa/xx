DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir .git
GEN="${WORK}/project/.git/xx_generated.sh"

cat <<'EEE' > xx.cjs
console.log("noise from config on stdout");
process.stdout.write("more noise\n");
module.exports = async (setup, ctx) => {
  await new Promise((res) => setTimeout(res, 5));
  return {
    env: { command: `echo "${process.env.XX_T14}"`, confirm: false },
    ctx: { command: `echo "${ctx.args.join("+")}|${ctx.cwd}|${ctx.configPath}"`, confirm: false },
    ...setup,
  };
};
EEE

OUT="$(XX_T14="injected value" "${BIN}" env 2>"${WORK}/err")"
assert_eq "${?}" "0" "exit code"
assert_eq "${OUT}" "${GEN}" "stdout is only the path"
assert_eq "$(cat "${OUT}")" 'echo "injected value"' "env var injected into the script"
assert_contains "$(cat "${WORK}/err")" "noise from config on stdout" "config output goes to stderr"

OUT="$(cat "$("${BIN}" ctx a 'b c' 2>/dev/null)")"
assert_eq "${OUT}" "echo \"a+b c|${WORK}/project|${WORK}/project/xx.cjs\"" "context"


rm xx.cjs
cat <<'EEE' > xx.mjs
export default () => ({ esm: { command: `echo from esm`, confirm: false } });
EEE
assert_eq "$(cat "$("${BIN}" esm)")" "echo from esm" "xx.mjs"

echo "  XX_T14='injected value' xx env"
exit 0
