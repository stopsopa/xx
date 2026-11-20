DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# json with absolute paths of templates from the repository
cat <<EEE > "${WORK}/init.json"
{
  "ts": "${ROOT}/templates/xx.ts",
  "js": "file://${ROOT}/templates/xx.js",
  "mjs": "${ROOT}/templates/xx.mjs",
  "cjs": "${ROOT}/templates/xx.cjs"
}
EEE
export XX_INIT_CONFIG="${WORK}/init.json"

# 1. default kind is ts, no .git -> ./xx.ts
OUT="$("${BIN}" --init 2>&1)"
assert_eq "${?}" "0" "exit code of --init without .git"
assert_contains "${OUT}" "${WORK}/project/xx.ts" "path in the output"
cmp -s xx.ts "${ROOT}/templates/xx.ts" || fail "./xx.ts differs from the template"
"${BIN}" --list > /dev/null || fail "template xx.ts doesn't load"

# 2. existing file is never overwritten
echo "mine" > xx.ts
OUT="$("${BIN}" --init 2>&1)"
assert_eq "${?}" "1" "exit code when target exists"
assert_contains "${OUT}" "already exist" "error when target exists"
assert_eq "$(cat xx.ts)" "mine" "existing file is untouched"
rm xx.ts

# 3. every kind, with .git -> .git/xx.<kind>, through the wrapper, and it loads
mkdir .git
for KIND in ts js mjs cjs; do
  OUT="$(/bin/bash -c "source \"${XXSH}\" --init ${KIND}" 2>&1)"
  assert_eq "${?}" "0" "exit code of --init ${KIND}"
  cmp -s ".git/xx.${KIND}" "${ROOT}/templates/xx.${KIND}" || fail ".git/xx.${KIND} differs from the template"
  assert_eq "$(ls -A .git)" "xx.${KIND}" "only .git/xx.${KIND} was created"
  "${BIN}" --list > /dev/null || fail "template xx.${KIND} doesn't load"
  rm ".git/xx.${KIND}"
done
assert_eq "$(ls -A)" ".git" "nothing created in pwd when .git exists"

OUT="$("${BIN}" --init yaml 2>&1)"
assert_eq "${?}" "1" "exit code of --init with unknown kind"
assert_contains "${OUT}" "unknown kind of the config >yaml<" "error for unknown kind"

# 4. --esm [path]: always the ts template, to given file or directory
OUT="$(/bin/bash -c "source \"${XXSH}\" --esm" 2>&1)"
assert_eq "${?}" "0" "exit code of --esm"
cmp -s .git/xx.ts "${ROOT}/templates/xx.ts" || fail "--esm: .git/xx.ts differs from the template"

mkdir sub
"${BIN}" --esm sub > /dev/null 2>&1
assert_eq "${?}" "0" "exit code of --esm <directory>"
cmp -s sub/xx.ts "${ROOT}/templates/xx.ts" || fail "--esm sub: sub/xx.ts differs from the template"

"${BIN}" --esm "${WORK}/elsewhere.ts" > /dev/null 2>&1
assert_eq "${?}" "0" "exit code of --esm <file>"
cmp -s "${WORK}/elsewhere.ts" "${ROOT}/templates/xx.ts" || fail "--esm <file> differs from the template"
rm .git/xx.ts

# 5. relative paths in the json are relative to the json, XX_INIT_CONFIG relative to pwd
mkdir "${WORK}/project/own"
echo "export default () => ({ own: { command: 'echo own' } });" > own/my.mjs
echo '{"mjs": "my.mjs"}' > own/init.json
XX_INIT_CONFIG="own/init.json" "${BIN}" --init mjs > /dev/null 2>&1
assert_eq "${?}" "0" "exit code with relative paths"
cmp -s .git/xx.mjs own/my.mjs || fail "relative paths: .git/xx.mjs differs"
rm .git/xx.mjs

# "~/" at the beginning: in XX_INIT_CONFIG and in paths inside of the json
cp own/my.mjs "${HOME}/home.mjs"
echo '{"mjs": "~/home.mjs"}' > "${HOME}/init.json"
XX_INIT_CONFIG="~/init.json" "${BIN}" --init mjs > /dev/null 2>&1
assert_eq "${?}" "0" "exit code with paths starting with ~/"
cmp -s .git/xx.mjs own/my.mjs || fail "paths starting with ~/: .git/xx.mjs differs"
rm .git/xx.mjs "${HOME}/home.mjs" "${HOME}/init.json"

# 6. errors: kind missing in json, broken json, missing json, missing template
OUT="$(XX_INIT_CONFIG="own/init.json" "${BIN}" --init ts 2>&1)"
assert_eq "${?}" "1" "exit code when kind is missing in json"
assert_contains "${OUT}" "key >ts< is missing" "error when kind is missing in json"

echo "not json" > "${WORK}/broken.json"
OUT="$(XX_INIT_CONFIG="${WORK}/broken.json" "${BIN}" --init 2>&1)"
assert_eq "${?}" "1" "exit code for broken json"
assert_contains "${OUT}" "it is not valid json" "error for broken json"

OUT="$(XX_INIT_CONFIG="${WORK}/missing.json" "${BIN}" --init 2>&1)"
assert_eq "${?}" "1" "exit code for missing json"
assert_contains "${OUT}" "XX_INIT_CONFIG=>${WORK}/missing.json<: can't read file" "error for missing json"

echo "{\"ts\": \"${WORK}/missing.ts\"}" > "${WORK}/dangling.json"
OUT="$(XX_INIT_CONFIG="${WORK}/dangling.json" "${BIN}" --init 2>&1)"
assert_eq "${?}" "1" "exit code for missing template"
assert_contains "${OUT}" "can't read file >${WORK}/missing.ts<" "error for missing template"

assert_eq "$(ls -A .git)" "" "nothing left in .git after failures"

# 7. init.json published in the repository points to the four templates of the repository
for KIND in ts js mjs cjs; do
  assert_contains "$(cat "${ROOT}/init.json")" "\"${KIND}\": \"https://raw.githubusercontent.com/stopsopa/xx/main/templates/xx.${KIND}\"" "init.json in the repository"
  [[ -f "${ROOT}/templates/xx.${KIND}" ]] || fail "templates/xx.${KIND} doesn't exist"
done

echo "  XX_INIT_CONFIG=/path/to/init.json xx --init ts"
exit 0
