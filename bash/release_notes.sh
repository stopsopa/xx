# Generates body of github release (markdown) to stdout.
#
#   /bin/bash bash/release_notes.sh <tag> <owner/repo> <directory with release files>
#
# example:
#   /bin/bash bash/release_notes.sh v1.0.0 stopsopa/xx release-dist
#
# The directory has to contain SHA256SUMS.txt (lines: "<hash>  <file>") for xx-* binaries and xx.sh.
#
# Body consist of:
#   1. section "## <tag>" from changelog.md (skipped if there is no such section)
#   2. download + checksum commands for each binary (always together with xx.sh),
#      files are saved to current directory, README.md continues from there
#   3. table of checksums
# Used by .github/workflows/rust.yml, can be executed locally to preview the result.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$(cd "${DIR}/.." && pwd)"

TAG="${1}"
REPO="${2}"
DIST="${3}"

if [[ -z "${TAG}" || -z "${REPO}" || -z "${DIST}" ]]; then
  echo "${0} error: usage: /bin/bash bash/release_notes.sh <tag> <owner/repo> <directory> - got TAG=>${TAG}< REPO=>${REPO}< DIST=>${DIST}<" >&2
  exit 1
fi

SUMS="${DIST}/SHA256SUMS.txt"

if [[ ! -f "${SUMS}" ]]; then
  echo "${0} error: file >${SUMS}< doesn't exist" >&2
  exit 1
fi

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

WRAPPER_HASH="$(awk '$2 == "xx.sh" { print $1 }' "${SUMS}")"

if [[ -z "${WRAPPER_HASH}" ]]; then
  echo "${0} error: xx.sh not found in >${SUMS}<" >&2
  exit 1
fi

# 1. everything between "## <tag>" and next "## " heading
CHANGES="$(awk -v tag="${TAG}" '
  /^## / { found = ($2 == tag); next }
  found { print }
' "${ROOT}/changelog.md")"

if [[ -n "${CHANGES//[[:space:]]/}" ]]; then
  cat <<EEE
${CHANGES}

EEE
fi

cat <<EEE
### Installation & Checksum Verification

Two files are needed, both from this release (they refuse to work together if their versions differ):

- the binary for your platform, saved as \`xx-bin\`
- the wrapper \`xx.sh\`

Pick the block for your platform. It downloads both files to the current directory and verifies checksums of both.
Then go back to [README.md → Installation → step 2](https://github.com/${REPO}#2-install) to copy them to their place and set up the shell.

EEE

while read -r HASH FILE; do
  if [[ "${FILE}" == "xx.sh" || -z "${FILE}" ]]; then
    continue
  fi

  cat <<EEE
#### \`${FILE}\`

\`\`\`bash
# Download via curl:
curl -fL -o xx-bin \\
  ${BASE_URL}/${FILE}
curl -fL -o xx.sh \\
  ${BASE_URL}/xx.sh

# Or download via wget:
wget -O xx-bin \\
  ${BASE_URL}/${FILE}
wget -O xx.sh \\
  ${BASE_URL}/xx.sh

# Verify checksums:
printf '%s\n' \\
  '${HASH}  xx-bin' \\
  '${WRAPPER_HASH}  xx.sh' \\
  | shasum -a 256 -c -
# (on Linux without shasum replace "shasum -a 256 -c -" with "sha256sum -c -")
# expected output:
#   xx-bin: OK
#   xx.sh: OK
\`\`\`

EEE
done < "${SUMS}"

cat <<EEE
### SHA-256 Checksums

| File | SHA-256 Checksum |
| --- | --- |
EEE

while read -r HASH FILE; do
  if [[ -n "${FILE}" ]]; then
    echo "| \`${FILE}\` | \`${HASH}\` |"
  fi
done < "${SUMS}"
