DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/../_lib.sh"

# xx --update: both files (xx.sh and the binary) replaced in one go, from a release.
# Releases are faked in a local directory (XX_RELEASES), with the same layout github has:
#   <dir>/latest                    tag of the latest release (github: redirect)
#   <dir>/download/<tag>/<file>

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) ASSET="xx-darwin-arm64" ;;
  Linux-x86_64) ASSET="xx-linux-x64" ;;
  Linux-aarch64 | Linux-arm64) ASSET="xx-linux-arm64" ;;
  *)
    echo "  skipped: no released binaries for $(uname -s)-$(uname -m)"
    exit 0
    ;;
esac

# --update refuses to touch local build (version "dev"), binaries with real versions are needed.
# build_version <version> <output>
build_version() {
  local BUILT="${ROOT}/target/release/xx"
  if [[ -n "${TARGET}" ]]; then
    XX_VERSION="${1}" HOME="${REAL_HOME}" cargo build --release --target "${TARGET}" --manifest-path "${ROOT}/Cargo.toml" > "${WORK}/cargo.log" 2>&1
    BUILT="${ROOT}/target/${TARGET}/release/xx"
  else
    XX_VERSION="${1}" HOME="${REAL_HOME}" cargo build --release --manifest-path "${ROOT}/Cargo.toml" > "${WORK}/cargo.log" 2>&1
  fi
  if [[ "${?}" != "0" ]]; then
    cat "${WORK}/cargo.log"
    fail "cargo build of version >${1}< failed"
  fi
  cp "${BUILT}" "${2}"
  assert_eq "$("${2}" --version)" "xx ${1}" "version of the binary built for the test"
}

sha256() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "${@}"
  else
    shasum -a 256 "${@}"
  fi
}

# release <directory of releases> <tag> <binary>
release() {
  local TARGET_DIR="${1}/download/${2}"
  mkdir -p "${TARGET_DIR}"
  cp "${3}" "${TARGET_DIR}/${ASSET}"
  /bin/bash "${ROOT}/bash/embed.sh" "${2}" "${TARGET_DIR}/xx.sh" "${TARGET_DIR}/${ASSET}" 2> /dev/null || fail "bash/embed.sh failed for >${2}<"
  (cd "${TARGET_DIR}" && sha256 "${ASSET}" xx.sh > SHA256SUMS.txt)
}

build_version v9.9.8 "${WORK}/bin-v9.9.8"
build_version v9.9.9 "${WORK}/bin-v9.9.9"

REL="${WORK}/releases"
release "${REL}" v9.9.8 "${WORK}/bin-v9.9.8"
release "${REL}" v9.9.9 "${WORK}/bin-v9.9.9"
echo "v9.9.9" > "${REL}/latest"

# installed: v9.9.8, the way README.md says
mkdir "${HOME}/.xx"
cp "${REL}/download/v9.9.8/${ASSET}" "${HOME}/.xx/xx-bin"
cp "${REL}/download/v9.9.8/xx.sh" "${HOME}/.xx/xx.sh"
chmod 755 "${HOME}/.xx/xx-bin"
chmod 600 "${HOME}/.xx/xx.sh"

export XX_BIN="~/.xx/xx-bin"
export XX_RELEASES="${REL}"

echo 'module.exports = () => ({ one: { command: `echo executed-one`, confirm: false } });' > xx.cjs

# xx <shell> <args...>
xx() {
  local SHELL_BIN="${1}"
  shift
  "${SHELL_BIN}" -c "source ~/.xx/xx.sh ${*}; echo \"code=\${?}\"" 2>&1
}

# installed <tag> <label>
installed() {
  cmp -s "${HOME}/.xx/xx-bin" "${REL}/download/${1}/${ASSET}" || fail "${2}: binary is not the one from ${1}"
  cmp -s "${HOME}/.xx/xx.sh" "${REL}/download/${1}/xx.sh" || fail "${2}: xx.sh is not the one from ${1}"
  assert_eq "$(ls -A "${HOME}/.xx" | sort | tr '\n' ' ')" "xx-bin xx.sh " "${2}: no other files left in the directory"
  assert_eq "$(xx /bin/bash --version)" "$(printf "xx.sh ${1}\nxx ${1}\ncode=0")" "${2}: xx --version in bash"
  assert_eq "$(xx zsh --version)" "$(printf "xx.sh ${1}\nxx ${1}\ncode=0")" "${2}: xx --version in zsh"
  assert_eq "$(xx zsh one)" "$(printf 'executed-one\ncode=0')" "${2}: commands work"
}

installed v9.9.8 "before"

# --check: only information
OUT="$(xx /bin/bash --update --check)"
assert_eq "${OUT}" "installed: v9.9.8
latest: v9.9.9
to install it: xx --update
code=0" "--update --check"
installed v9.9.8 "after --check"

# answer "no"
OUT="$(XX_TEST_KEYS="n" xx /bin/bash --update)"
assert_contains "${OUT}" "nothing changed" "answer no"
assert_contains "${OUT}" "code=0" "answer no: exit code"
installed v9.9.8 "after answer no"

# release with broken download: checksum doesn't match
BAD="${WORK}/releases-bad-checksum"
cp -R "${REL}" "${BAD}"
echo "x" >> "${BAD}/download/v9.9.9/${ASSET}"
OUT="$(XX_RELEASES="${BAD}" XX_CONFIRM=false xx /bin/bash --update)"
assert_contains "${OUT}" "checksum of downloaded >${ASSET}< doesn't match" "broken download"
assert_contains "${OUT}" "code=1" "broken download: exit code"
installed v9.9.8 "after broken download"

# release where checksums are fine, but xx.sh was built for other binary: caught by the test of the pair
BAD="${WORK}/releases-bad-pair"
cp -R "${REL}" "${BAD}"
cp "${REL}/download/v9.9.8/xx.sh" "${BAD}/download/v9.9.9/xx.sh"
(cd "${BAD}/download/v9.9.9" && sha256 "${ASSET}" xx.sh > SHA256SUMS.txt)
OUT="$(XX_RELEASES="${BAD}" XX_CONFIRM=false xx /bin/bash --update)"
assert_contains "${OUT}" "downloaded files don't work together, nothing was changed" "files of the release don't match each other"
assert_contains "${OUT}" "code=1" "files of the release don't match each other: exit code"
installed v9.9.8 "after release with not matching files"

# release which doesn't exist
OUT="$(XX_CONFIRM=false xx /bin/bash --update v1.2.3)"
assert_contains "${OUT}" "is >v1.2.3< a published release with all files?" "not existing release"
assert_contains "${OUT}" "code=1" "not existing release: exit code"
installed v9.9.8 "after not existing release"

# the update, from bash, confirmed with Enter
OUT="$(XX_TEST_KEYS="enter" xx /bin/bash --update)"
assert_contains "${OUT}" "xx updated: v9.9.8 -> v9.9.9" "update"
assert_contains "${OUT}" "test ok: installed xx.sh works with installed binary" "update: pair tested after replacing"
assert_contains "${OUT}" "code=0" "update: exit code"
installed v9.9.9 "after update"
assert_eq "$(stat -f '%Lp' "${HOME}/.xx/xx.sh" 2> /dev/null || stat -c '%a' "${HOME}/.xx/xx.sh")" "600" "xx.sh keeps its permissions"

echo "  xx --update   (v9.9.8 installed, v9.9.9 is the latest), what the user sees:"
echo "${OUT}" | sed "s|${WORK}|<tmp>|g; s|^|    |"

# nothing to do
OUT="$(xx zsh --update)"
assert_eq "${OUT}" "installed: v9.9.9
latest: v9.9.9
xx is up to date
code=0" "up to date"

# given release, also older one, this time from zsh (the wrapper finds its own path differently)
OUT="$(XX_CONFIRM=false xx zsh --update v9.9.8)"
assert_contains "${OUT}" "xx updated: v9.9.9 -> v9.9.8" "downgrade"
assert_contains "${OUT}" "code=0" "downgrade: exit code"
installed v9.9.8 "after downgrade"

# the binary alone doesn't know where xx.sh is
OUT="$(XX_CONFIRM=false "${HOME}/.xx/xx-bin" --update 2>&1)"
assert_contains "${OUT}" "--update has to be called through xx.sh" "binary executed directly"
installed v9.9.8 "after executing the binary directly"

# local build is not a release
OUT="$(XX_BIN="${BIN}" /bin/bash -c "source \"${XXSH}\" --update; echo \"code=\${?}\"" 2>&1)"
assert_contains "${OUT}" "this binary is a local build (version >dev<)" "local build"
assert_contains "${OUT}" "code=1" "local build: exit code"

exit 0
