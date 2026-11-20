DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

CONFIG='module.exports = () => ({ one: { command: `echo one`, confirm: false } });'

# ./xx.cjs, no .git -> ${XX_TMP}/xx-<uid>/<hash of pwd>.sh
echo "${CONFIG}" > xx.cjs
FIRST="$("${BIN}" one)"
if [[ "${FIRST}" != "${TMP_GEN_DIR}/"*.sh ]]; then
  fail "./xx.cjs without .git: expected file in >${TMP_GEN_DIR}< got >${FIRST}<"
fi
assert_eq "$(cat "${FIRST}")" "echo one" "content of the script in tmp"
assert_eq "$(ls -ld "${TMP_GEN_DIR}" | cut -c1-10)" "drwx------" "tmp directory is private"
assert_eq "$("${BIN}" one)" "${FIRST}" "the same directory, the same file"

# other directory -> other file, two terminals can't overwrite each other's script
mkdir "${WORK}/other"
cp xx.cjs "${WORK}/other/xx.cjs"
SECOND="$(cd "${WORK}/other" && "${BIN}" one)"
if [[ "${SECOND}" != "${TMP_GEN_DIR}/"*.sh || "${SECOND}" == "${FIRST}" ]]; then
  fail "other directory: expected different file in >${TMP_GEN_DIR}< got >${SECOND}< (first >${FIRST}<)"
fi

# XX_TMP not defined: TMPDIR of the system is used
mkdir "${WORK}/systmp"
THIRD="$(unset XX_TMP; TMPDIR="${WORK}/systmp" "${BIN}" one)"
if [[ "${THIRD}" != "${WORK}/systmp/xx-$(id -u)/"*.sh ]]; then
  fail "without XX_TMP: expected file in >${WORK}/systmp/xx-$(id -u)< got >${THIRD}<"
fi

# XX_TMP wins over TMPDIR
assert_eq "$(TMPDIR="${WORK}/systmp" "${BIN}" one)" "${FIRST}" "XX_TMP wins over TMPDIR"

# nothing lands in home anymore
assert_eq "$(ls -A "${HOME}")" "" "home is untouched"

# ./xx.cjs, .git exists
mkdir .git
assert_eq "$("${BIN}" one)" "${WORK}/project/.git/xx_generated.sh" "./xx.cjs with .git"

# .git/xx.cjs
mv xx.cjs .git/xx.cjs
assert_eq "$("${BIN}" one)" "${WORK}/project/.git/xx_generated.sh" ".git/xx.cjs"

# ~/xx.cjs is the last place, also when .git exists. Script goes to tmp
mv .git/xx.cjs "${HOME}/xx.cjs"
assert_eq "$("${BIN}" one)" "${FIRST}" "~/xx.cjs"

# worktree: .git is a file
rm -rf .git "${HOME}/xx.cjs"
mkdir -p "${WORK}/realgit"
echo "gitdir: ${WORK}/realgit" > .git
echo "${CONFIG}" > xx.cjs
assert_eq "$("${BIN}" one)" "${WORK}/realgit/xx_generated.sh" ".git as a file"

# tmp directory prepared by somebody else (here: writable by others) is refused
rm .git
chmod 777 "${TMP_GEN_DIR}"
OUT="$("${BIN}" one 2>&1)"
assert_eq "${?}" "1" "exit code when tmp directory is writable by others"
assert_contains "${OUT}" "writable by other users" "error when tmp directory is writable by others"
chmod 700 "${TMP_GEN_DIR}"

echo "  xx one   (checking location of xx_generated.sh)"
exit 0
