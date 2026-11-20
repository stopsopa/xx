DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/bash/detect_arch.sh"
BIN="${XX_BIN_PATH}"

GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

if [[ ! -f "${BIN}" ]]; then
  echo "${0} error: binary not found at >${BIN}<. Run compile.sh first."
  exit 1
fi

TOTAL=0
PASSED=0
FAILED=0

echo "${YELLOW}=== Running xx unit tests (cargo test) ===${RESET}"
echo ""

cargo test --manifest-path "${DIR}/Cargo.toml"

if [[ "${?}" -ne 0 ]]; then
  echo "${0} error: cargo test failed"
  exit 1
fi

echo ""
echo "${YELLOW}=== Running xx test suite ===${RESET}"
echo ""

for test_script in "${DIR}"/test/test*/test.sh; do
  test_dir="$(dirname "${test_script}")"
  test_name="$(basename "${test_dir}")"

  TOTAL=$((TOTAL + 1))
  echo -n "Running ${test_name}... "

  OUTPUT=$(/bin/bash "${test_script}" 2>&1)
  STATUS=$?

  if [[ "${STATUS}" -eq 0 ]]; then
    PASSED=$((PASSED + 1))
    echo "${GREEN}PASS${RESET}"
    if [[ -n "${OUTPUT}" ]]; then
      echo "${OUTPUT}"
    fi
  else
    FAILED=$((FAILED + 1))
    echo "${RED}FAIL (exit code ${STATUS})${RESET}"
    if [[ -n "${OUTPUT}" ]]; then
      echo "${OUTPUT}"
    fi
  fi
  echo ""
done

echo "Total tests: ${TOTAL}"
echo "Passed: ${PASSED}"
echo "Failed: ${FAILED}"

if [[ "${FAILED}" -gt 0 ]]; then
  echo "${RED}Some tests failed!${RESET}"
  exit 1
fi

echo "${GREEN}All tests passed successfully!${RESET}"
exit 0
