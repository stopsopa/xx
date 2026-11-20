DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/bash/detect_arch.sh"

GREEN=$'\033[32m'
RESET=$'\033[0m'

echo "Building for target '${TARGET}' (arch: ${ARCH_DIR})..."

export XX_VERSION="dev"

if [[ -n "${TARGET}" ]]; then
  cargo build --release --target "${TARGET}" --manifest-path "${DIR}/Cargo.toml"
  BUILD_STATUS=$?
else
  cargo build --release --manifest-path "${DIR}/Cargo.toml"
  BUILD_STATUS=$?
fi

if [[ "${BUILD_STATUS}" -ne 0 ]]; then
  echo "${0} error: cargo build failed with exit code >${BUILD_STATUS}<"
  exit "${BUILD_STATUS}"
fi

mkdir -p "${DIR}/bin/${ARCH_DIR}"

SRC_BIN="${DIR}/target/${TARGET}/release/xx"
if [[ ! -f "${SRC_BIN}" ]]; then
  SRC_BIN="${DIR}/target/release/xx"
fi

if [[ ! -f "${SRC_BIN}" ]]; then
  echo "${0} error: built binary not found at >${SRC_BIN}<"
  exit 1
fi

cp "${SRC_BIN}" "${XX_BIN_PATH}"

echo "${GREEN}Done. Binary written to bin/${ARCH_DIR}/xx${RESET}"

