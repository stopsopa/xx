DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

cat <<'EEE' > xx.cjs
module.exports = () => ({
  opts: { command: `echo "NODE_OPTIONS=${process.env.NODE_OPTIONS}"`, confirm: false },
});
EEE

NODE="${XX_NODE_BINARY}"

# 1. not defined
OUT="$(unset XX_NODE_BINARY; "${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "exit code when XX_NODE_BINARY is not defined"
assert_contains "${OUT}" "env var XX_NODE_BINARY is not defined" "error when not defined"
assert_contains "${OUT}" "export XX_NODE_BINARY=" "error says how to define it"

# node from PATH is never used as a fallback
OUT="$(unset XX_NODE_BINARY; PATH="$(dirname "${NODE}"):${PATH}" "${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "exit code when node is only in PATH"

# 2. points to nothing
OUT="$(XX_NODE_BINARY="${WORK}/nothing" "${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "exit code when XX_NODE_BINARY points to nothing"
assert_contains "${OUT}" "XX_NODE_BINARY=>${WORK}/nothing< - file doesn't exist" "error when points to nothing"

# 3. points to a file which is not executable
echo "not a program" > "${WORK}/plain"
OUT="$(XX_NODE_BINARY="${WORK}/plain" "${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "exit code when XX_NODE_BINARY is not executable"
assert_contains "${OUT}" "can't execute it" "error when not executable"

# 4. points to a program which is not node
OUT="$(XX_NODE_BINARY="${FAKE}" "${BIN}" --list 2>&1)"
assert_eq "${?}" "1" "exit code when XX_NODE_BINARY is not node"
assert_contains "${OUT}" "it doesn't look like node" "error when not node"
assert_contains "${OUT}" "XX_NODE_BINARY=>${FAKE}< - it doesn't look like node" "error names the program"
assert_contains "${OUT}" "stdout:    >I am something else<" "error shows what the program answered"

# 5. checked on every run which needs node: also direct run, --gen, --init, through the wrapper
for ARGS in "opts" "--gen opts" "--init" "--esm"; do
  OUT="$(XX_NODE_BINARY="${FAKE}" "${BIN}" ${ARGS} 2>&1)"
  assert_eq "${?}" "1" "exit code of >xx ${ARGS}< when XX_NODE_BINARY is not node"
  assert_contains "${OUT}" "it doesn't look like node" "error of >xx ${ARGS}<"
done
OUT="$(XX_NODE_BINARY="${FAKE}" /bin/bash -c "source \"${XXSH}\" opts; echo \"code=\${?}\"" 2>&1)"
assert_contains "${OUT}" "it doesn't look like node" "error through the wrapper"
assert_contains "${OUT}" "code=1" "return code through the wrapper"

# "~/" at the beginning means home directory (the shell doesn't expand it inside of quotes)
ln -s "${NODE}" "${HOME}/node-link"
OUT="$(XX_NODE_BINARY="~/node-link" "${BIN}" --list 2>&1)"
assert_eq "${OUT}" "  1 - opts" "XX_NODE_BINARY starting with ~/"

OUT="$(XX_NODE_BINARY="~/no-node-here" "${BIN}" --list 2>&1)"
assert_contains "${OUT}" "XX_NODE_BINARY=>${HOME}/no-node-here< - file doesn't exist" "error shows expanded path"

# --help and --version work without node, to be able to read about XX_NODE_BINARY
OUT="$(unset XX_NODE_BINARY; "${BIN}" --help)"
assert_eq "${?}" "0" "--help without XX_NODE_BINARY"
assert_contains "${OUT}" "XX_NODE_BINARY" "--help describes XX_NODE_BINARY"

# 6. NODE_OPTIONS: passed as it is when XX_NODE_OPTIONS is not defined
OUT="$(cat "$(NODE_OPTIONS="--no-warnings" "${BIN}" opts)")"
assert_eq "${OUT}" 'echo "NODE_OPTIONS=--no-warnings"' "NODE_OPTIONS is passed through"

# replaced when XX_NODE_OPTIONS is defined
OUT="$(cat "$(NODE_OPTIONS="--no-warnings" XX_NODE_OPTIONS="--no-deprecation" "${BIN}" opts)")"
assert_eq "${OUT}" 'echo "NODE_OPTIONS=--no-deprecation"' "XX_NODE_OPTIONS replaces NODE_OPTIONS"

# also when it is defined as empty: that is the way to clear NODE_OPTIONS only for xx
OUT="$(cat "$(NODE_OPTIONS="--no-warnings" XX_NODE_OPTIONS="" "${BIN}" opts)")"
assert_eq "${OUT}" 'echo "NODE_OPTIONS="' "empty XX_NODE_OPTIONS clears NODE_OPTIONS"

# broken options are reported by the check, with both values shown
OUT="$(XX_NODE_OPTIONS="--no-such-option-xx" "${BIN}" opts 2>&1)"
assert_eq "${?}" "1" "exit code with broken XX_NODE_OPTIONS"
assert_contains "${OUT}" "XX_NODE_OPTIONS: >--no-such-option-xx<" "error shows XX_NODE_OPTIONS"

echo "  XX_NODE_BINARY=/path/to/something-else xx --list"
exit 0
