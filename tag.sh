# Creates and pushes the next version tag. The pushed tag starts the release
# (.github/workflows/rust.yml), and the tag is the version of the released binaries.
#
#   /bin/bash tag.sh           choose patch / minor / major from a list (needs node)
#   /bin/bash tag.sh patch     x.y.Z+1
#   /bin/bash tag.sh minor     x.Y+1.0
#   /bin/bash tag.sh major     X+1.0.0
#
# The same through the menu: xx publish [patch|minor|major]
# Before it: add section "## <new tag>" to changelog.md, it becomes the top of the release page
# (preview: xx "release notes preview" <new tag>).

_SHELL="$(ps -p $$ -o comm=)"; # bash || sh || zsh
_SHELL="$(basename ${_SHELL//-/})"
case ${_SHELL} in
  zsh)
    _DIR="$( cd "$( dirname "${(%):-%x}" )" && pwd -P )"
    ;;
  sh)
    # be carefull this will not work when sourcing this file in sh shell
    # will though work when called /bin/sh my_script.sh from any shell
    _DIR="$( cd "$( dirname "${0}" )" && pwd -P )"
    ;;
  *)
    _DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
    ;;
esac

GRAY=$'\033[38;5;244m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
REVERSE=$'\033[7m'
RESET=$'\033[0m'

MODE="${1}"

# no argument: choose from the list
if [[ -z "${MODE}" ]]; then
  MODE="$(printf "patch\nminor\nmajor\n" | NODE_OPTIONS= node "${_DIR}/bash/file/fuzzy.ts")"
  if [[ "${?}" -ne 0 || -z "${MODE}" ]]; then
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

cd "${_DIR}" || exit 1

echo "${GRAY}Fetching git tags...${RESET}"
FETCH_OUTPUT="$(git fetch --tags 2>&1)"
FETCH_CODE="${?}"
echo "${FETCH_OUTPUT}"

if [[ "${FETCH_CODE}" -ne 0 ]]; then

  # Tags which exist locally and on origin but point to different commits. Usually after rewriting
  # history (git filter-branch, rebase): local tag was moved to the new commit, origin still has the old one.
  CLOBBERED="$(echo "${FETCH_OUTPUT}" | sed -nE 's/^ ! \[rejected\] +([^ ]+) +-> .*\(would clobber existing tag\)$/\1/p')"

  if [[ -z "${CLOBBERED}" ]]; then
    echo "${0} error: git fetch --tags failed"
    exit 1
  fi

  TAGS_LIST=""
  TAGS_ARGS=()
  while IFS= read -r TAG; do
    LOCAL_COMMIT="$(git rev-parse --short "${TAG}^{commit}" 2> /dev/null)"
    # for annotated tag the second line (^{}) is the commit, for lightweight tag there is only one line
    REMOTE_COMMIT="$(git ls-remote --tags origin "refs/tags/${TAG}" "refs/tags/${TAG}^{}" | tail -n 1 | cut -c1-7)"
    TAGS_LIST="${TAGS_LIST}  ${TAG}   local: ${LOCAL_COMMIT}   origin: ${REMOTE_COMMIT}"$'\n'
    TAGS_ARGS+=("${TAG}")
  done <<< "${CLOBBERED}"

  cat <<EEE
${YELLOW}
Tags below point to different commit locally than on origin:
${RESET}
${TAGS_LIST}
${YELLOW}It usually happens after rewriting history (git filter-branch, rebase): local tag was moved to
the new commit, but origin still has the old one. Two ways to fix it:${RESET}

  ${CYAN}local${RESET}   git push --force origin ${TAGS_ARGS[*]}
          origin gets local tags - pick it if you rewrote the history on purpose.
          Pushed tag starts the release again for that tag.

  ${CYAN}remote${RESET}  git fetch --tags --force
          local tags are replaced with those from origin, nothing is pushed, no release.
          Tag stays on the old commit (old history is still reachable on origin through it).

EEE

  FIX="$(printf "local\nremote\nabort\n" | NODE_OPTIONS= node "${_DIR}/bash/file/fuzzy.ts")"

  if [[ "${FIX}" == "local" ]]; then
    git push --force origin "${TAGS_ARGS[@]}" || {
      echo "${0} error: git push --force origin ${TAGS_ARGS[*]} failed"
      exit 1
    }
  elif [[ "${FIX}" == "remote" ]]; then
    git fetch --tags --force || {
      echo "${0} error: git fetch --tags --force failed"
      exit 1
    }
  else
    echo "${0} error: git fetch --tags failed, tags >${TAGS_ARGS[*]}< differ between local and origin, nothing was changed"
    exit 1
  fi

  # now it has to pass
  git fetch --tags || {
    echo "${0} error: git fetch --tags still fails after fix >${FIX}<"
    exit 1
  }
fi

LATEST_TAG="$(git tag -l --sort=v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1)"

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

if ! grep -q "^## ${NEW_TAG}\$" "${_DIR}/changelog.md" 2> /dev/null; then
  echo "${YELLOW}warning: no section '## ${NEW_TAG}' in changelog.md, release page will have no description of changes${RESET}"
fi

# What is about to happen on its own lines, and below it a separate line in reverse colors
# which stays at the bottom with the cursor: it is visible that the script waits for a key.
cat <<EEE

${BOLD}About to create and push tag:${RESET} ${GREEN}${BOLD}${NEW_TAG}${RESET}
${GRAY}(the pushed tag starts the release)${RESET}

EEE

printf '%s' "${REVERSE}${YELLOW}${BOLD} WAITING ${RESET} ${YELLOW}press ${BOLD}Enter${RESET}${YELLOW} to continue, ${BOLD}Esc${RESET}${YELLOW} or ${BOLD}Ctrl+C${RESET}${YELLOW} to abort:${RESET} "

# One key at a time, without waiting for Enter, otherwise Esc could not be noticed:
#   Enter                    continue
#   Esc, q, n, Ctrl+D        abort
#   end of input             abort, it must not be treated as Enter
#   anything else            ignored, still waiting
while true; do
  IFS= read -r -s -n 1 KEY || {
    echo ""
    echo "${0} error: aborted"
    exit 1
  }

  if [[ -z "${KEY}" ]]; then
    echo ""
    break
  fi

  if [[ "${KEY}" == $'\033' || "${KEY}" == $'\004' || "${KEY}" == "q" || "${KEY}" == "n" ]]; then
    # arrows and function keys also start with Esc and send more characters right after it.
    # They are read here (waiting max 0.1 sec), otherwise they would land in the prompt of the shell
    if [[ "${KEY}" == $'\033' && -t 0 ]]; then
      STTY_OLD="$(stty -g)"
      stty -icanon -echo min 0 time 1
      dd bs=16 count=1 > /dev/null 2>&1
      stty "${STTY_OLD}"
    fi
    echo ""
    echo "${0}: aborted, nothing was created"
    exit 1
  fi
done

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
