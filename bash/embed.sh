# Generates xx.sh which accepts given binaries and nothing else:
# embeds version and md5 hashes of the binaries into a copy of xx.sh from the repository.
#
#   /bin/bash bash/embed.sh <version> <output xx.sh> <binary> [<binary> ...]
#
# examples:
#   /bin/bash bash/embed.sh dev bin/arm64/xx.sh bin/arm64/xx                (compile.sh does this)
#   /bin/bash bash/embed.sh v1.0.0 release-dist/xx.sh release-dist/xx-*     (release workflow does this)
#
# xx.sh computes md5 of the file from XX_BIN on every call and refuses to work if it is not
# on the embedded list. xx.sh in the repository has the list empty.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$(cd "${DIR}/.." && pwd)"

SOURCE="${ROOT}/xx.sh"

VERSION="${1}"
OUTPUT="${2}"

if [[ -z "${VERSION}" || -z "${OUTPUT}" || "${#}" -lt 3 ]]; then
  echo "${0} error: usage: /bin/bash bash/embed.sh <version> <output xx.sh> <binary> [<binary> ...] - got VERSION=>${VERSION}< OUTPUT=>${OUTPUT}< and >$(( ${#} > 2 ? ${#} - 2 : 0 ))< binaries" >&2
  exit 1
fi

shift 2

if [[ ! "${VERSION}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "${0} error: VERSION=>${VERSION}< contains characters other than letters, digits, dot, dash and underscore" >&2
  exit 1
fi

md5_of() {
  if command -v md5sum > /dev/null 2>&1; then
    md5sum "${1}" | cut -d ' ' -f 1
  elif command -v md5 > /dev/null 2>&1; then
    md5 -q "${1}"
  fi
}

LIST=""

for BINARY in "${@}"; do
  if [[ ! -f "${BINARY}" ]]; then
    echo "${0} error: binary >${BINARY}< doesn't exist" >&2
    exit 1
  fi

  HASH="$(md5_of "${BINARY}")"

  if [[ ! "${HASH}" =~ ^[0-9a-f]{32}$ ]]; then
    echo "${0} error: can't compute md5 of >${BINARY}< (is md5sum or md5 installed?), got >${HASH}<" >&2
    exit 1
  fi

  LIST="${LIST:+${LIST} }${HASH}"
done

# both lines have to be in xx.sh exactly once and exactly in this shape
for LINE in '__XX_VERSION="dev"' '__XX_BIN_MD5=""'; do
  COUNT="$(grep -c -x -F "${LINE}" "${SOURCE}")"
  if [[ "${COUNT}" != "1" ]]; then
    echo "${0} error: line >${LINE}< found >${COUNT}< times in >${SOURCE}<, expected exactly once" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "${OUTPUT}")"

sed \
  -e "s/^__XX_VERSION=\"dev\"\$/__XX_VERSION=\"${VERSION}\"/" \
  -e "s/^__XX_BIN_MD5=\"\"\$/__XX_BIN_MD5=\"${LIST}\"/" \
  "${SOURCE}" > "${OUTPUT}"

if ! grep -q -x -F "__XX_VERSION=\"${VERSION}\"" "${OUTPUT}" || ! grep -q -x -F "__XX_BIN_MD5=\"${LIST}\"" "${OUTPUT}"; then
  echo "${0} error: version or md5 was not embedded in >${OUTPUT}<" >&2
  exit 1
fi

echo "${0}: generated >${OUTPUT}< version >${VERSION}< md5 >${LIST}<" >&2
