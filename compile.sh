# Builds the xx binary for the machine it is executed on.
#
#   /bin/bash compile.sh
#
# Result:
#   bin/<arch>/xx      the binary
#   bin/<arch>/xx.sh   the wrapper which accepts exactly that binary (md5 embedded, bash/embed.sh).
#                      It has to be regenerated after every build, that's why it is done here.
#
# stdout: only absolute paths of binaries found in bin/ after the build, one per line
#         (every binary which is there, however many), so it can be consumed by other scripts:
#           export XX_BIN="$(/bin/bash compile.sh | head -n 1)"
# stderr: everything else (progress, errors)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/bash/detect_arch.sh"

GREEN=$'\033[32m'
RESET=$'\033[0m'

echo "Building for target '${TARGET}' (arch: ${ARCH_DIR})..." >&2

export XX_VERSION="dev"

if [[ -n "${TARGET}" ]]; then
  cargo build --release --target "${TARGET}" --manifest-path "${DIR}/Cargo.toml"
  BUILD_STATUS=$?
else
  cargo build --release --manifest-path "${DIR}/Cargo.toml"
  BUILD_STATUS=$?
fi

if [[ "${BUILD_STATUS}" -ne 0 ]]; then
  echo "${0} error: cargo build failed with exit code >${BUILD_STATUS}<" >&2
  exit "${BUILD_STATUS}"
fi

mkdir -p "${DIR}/bin/${ARCH_DIR}"

SRC_BIN="${DIR}/target/${TARGET}/release/xx"
if [[ ! -f "${SRC_BIN}" ]]; then
  SRC_BIN="${DIR}/target/release/xx"
fi

if [[ ! -f "${SRC_BIN}" ]]; then
  echo "${0} error: built binary not found at >${SRC_BIN}<" >&2
  exit 1
fi

cp "${SRC_BIN}" "${XX_BIN_PATH}"

/bin/bash "${DIR}/bash/embed.sh" "${XX_VERSION}" "${XX_SH_PATH}" "${XX_BIN_PATH}" || {
  echo "${0} error: the binary was built >${XX_BIN_PATH}< but generating the wrapper >${XX_SH_PATH}< failed, see the explanation above" >&2
  exit 1
}

echo "${GREEN}Done. Binaries:${RESET}" >&2

find "${DIR}/bin" -type f -name xx | sort

