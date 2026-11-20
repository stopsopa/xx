DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

mkdir .git

# 1. priority: all twelve exist, the winner is removed one by one
ORDER=""
for PLACE in .git . "${HOME}"; do
  for EXT in ts js mjs cjs; do
    FLAVOUR="esm"
    if [[ "${EXT}" = "ts" ]]; then FLAVOUR="ts"; fi
    if [[ "${EXT}" = "cjs" ]]; then FLAVOUR="cjs"; fi
    FILE="${PLACE}/xx.${EXT}"
    write_config "${FILE}" "${FLAVOUR}" "from ${FILE}"
    ORDER="${ORDER}${FILE}"$'\n'
  done
done

while read -r FILE; do
  if [[ -z "${FILE}" ]]; then
    continue
  fi
  assert_eq "$("${BIN}" --list 2>&1)" "  1 - from ${FILE}" "config which wins"
  rm "${FILE}"
done <<< "${ORDER}"

# 2. "type" in package.json decides about xx.js and xx.ts, never about xx.mjs and xx.cjs
echo '{"type": "module"}' > package.json
check_config xx.js esm 'type module: ./xx.js as es module'
check_config xx.ts ts 'type module: ./xx.ts'
check_config xx.cjs cjs 'type module: ./xx.cjs is still commonjs'
check_config .git/xx.js esm 'type module: .git/xx.js obeys package.json of the project'

write_config xx.js cjs "wrong"
OUT="$("${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "type module: commonjs in xx.js fails"
assert_contains "${OUT}" "loading config >${WORK}/project/xx.js< failed" "type module: commonjs in xx.js error"
rm xx.js

echo '{"type": "commonjs"}' > package.json
check_config xx.js cjs 'type commonjs: ./xx.js as commonjs'
check_config xx.mjs esm 'type commonjs: ./xx.mjs is still es module'

echo '{"name": "no-type"}' > package.json
check_config xx.js esm 'no type: ./xx.js as es module'
check_config xx.js cjs 'no type: ./xx.js as commonjs'
check_config xx.ts ts 'no type: ./xx.ts'

echo "  xx --list   (priority of 12 locations, \"type\" in package.json)"
exit 0
