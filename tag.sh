DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

GRAY=$'\033[38;5;244m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

MODE="${1}"

if [[ -z "${MODE}" ]]; then
  MODE="$(printf "patch\nminor\nmajor\n" | NODE_OPTIONS= node --experimental-strip-types "${DIR}/bash/file/fuzzy.ts")"
  if [[ $? -ne 0 || -z "${MODE}" ]]; then
    echo "${0} error: no mode selected"
    exit 1
  fi
fi

if [[ "${MODE}" != "patch" && "${MODE}" != "minor" && "${MODE}" != "major" ]]; then
  cat <<EEE
${YELLOW}Usage:${RESET}
  /bin/bash tag.sh patch
  /bin/bash tag.sh minor
  /bin/bash tag.sh major

${CYAN}Options:${RESET}
  patch  - Increment patch version (x.y.Z+1)
  minor  - Increment minor version (x.Y+1.0)
  major  - Increment major version (X+1.0.0)
EEE
  exit 1
fi

echo "${GRAY}Fetching git tags...${RESET}"
git fetch --tags || {
  echo "${0} error: git fetch --tags failed"
  exit 1
}

ALL_TAGS="$(git tag -l)"

LATEST_TAG=""
if [[ -n "${ALL_TAGS}" ]]; then
  LATEST_TAG="$(git tag -l --sort=v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1)"
fi

# first tag ever gets "v" prefix too (v0.0.1), otherwise the prefix is taken from the latest tag
V_PREFIX="v"
if [[ -z "${LATEST_TAG}" ]]; then
  LATEST_TAG="0.0.0"
  MAJOR=0
  MINOR=0
  PATCH=0
else
  RAW_TAG="${LATEST_TAG}"
  V_PREFIX=""
  if [[ "${RAW_TAG}" =~ ^v ]]; then
    V_PREFIX="v"
    RAW_TAG="${RAW_TAG#v}"
  fi
  MAJOR="$(echo "${RAW_TAG}" | cut -d. -f1)"
  MINOR="$(echo "${RAW_TAG}" | cut -d. -f2)"
  PATCH="$(echo "${RAW_TAG}" | cut -d. -f3)"
fi

if [[ "${MODE}" == "patch" ]]; then
  PATCH=$((PATCH + 1))
elif [[ "${MODE}" == "minor" ]]; then
  MINOR=$((MINOR + 1))
  PATCH=0
elif [[ "${MODE}" == "major" ]]; then
  MAJOR=$((MAJOR + 1))
  MINOR=0
  PATCH=0
fi

NEW_TAG="${V_PREFIX}${MAJOR}.${MINOR}.${PATCH}"

cat <<EEE

${BOLD}Previous tag:${RESET} ${YELLOW}${LATEST_TAG}${RESET}
${BOLD}Mode:${RESET}         ${CYAN}${MODE}${RESET}
${BOLD}New tag:${RESET}      ${GREEN}${NEW_TAG}${RESET}
${BOLD}Commit:${RESET}       $(git log -1 --format='%h %s')

EEE

# The tag is put on current commit with what is committed, warn about everything what
# makes the release different from what you see in the working directory

if [[ -n "$(git status --porcelain)" ]]; then
  echo "${YELLOW}warning: there are uncommitted changes, they will NOT be part of the release${RESET}"
fi

if [[ -z "$(git branch -r --contains HEAD 2> /dev/null)" ]]; then
  echo "${YELLOW}warning: current commit is not pushed to any remote branch (the tag will be pushed with it anyway)${RESET}"
fi

if ! grep -q "^## ${NEW_TAG}\$" "${DIR}/changelog.md" 2> /dev/null; then
  echo "${YELLOW}warning: no section '## ${NEW_TAG}' in changelog.md, release page will have no description of changes${RESET}"
fi

# Ctrl+D (end of input) must not be treated as Enter
read -r -p "Press Enter to create and push tag '${NEW_TAG}', or Ctrl+C to abort..." || {
  echo ""
  echo "${0} error: aborted"
  exit 1
}

git tag "${NEW_TAG}" || {
  echo "${0} error: failed to create tag >${NEW_TAG}<"
  exit 1
}

git push origin "${NEW_TAG}" || {
  # without this next run would see the local tag and skip a version
  git tag -d "${NEW_TAG}"
  echo "${0} error: failed to push tag >${NEW_TAG}< to remote, local tag removed"
  exit 1
}

echo "${GREEN}Successfully created and pushed tag >${NEW_TAG}<${RESET}"
