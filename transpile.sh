# Generates the templates downloaded by "xx --init js|mjs|cjs" from the only one which is
# maintained by hand:
#
#   templates/xx.ts  ->  templates/xx.js    es module
#                        templates/xx.mjs   es module
#                        templates/xx.cjs   commonjs
#
#   /bin/bash transpile.sh
#
# Generated files are not committed (.gitignore). They are created:
#   - by .github/workflows/pages.yml just before publishing GitHub Pages,
#     that is where "xx --init" downloads them from (see init.json)
#   - by test.sh, tests of --init use them
#
# How: esbuild removes the types (bash/transpile.mjs), then every generated file is loaded
# and has to return exactly the same commands as xx.ts.
#
# Requires: node 22.18+ and "npm ci" executed once (installs esbuild from package.json).
#
# stdout: only absolute paths of generated files, one per line
# stderr: everything else

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "${DIR}/templates/xx.ts" ]]; then
  echo "${0} error: source template >${DIR}/templates/xx.ts< doesn't exist" >&2
  exit 1
fi

if [[ ! -d "${DIR}/node_modules/esbuild" ]]; then
  cat <<EEE >&2
${0} error: esbuild is not installed >${DIR}/node_modules/esbuild<, run once:

    (cd "${DIR}" && npm ci)

EEE
  exit 1
fi

# XX_NODE_BINARY if defined (the node xx itself uses), otherwise node from PATH.
# NODE_OPTIONS is cleared: whatever is set in the shell (--inspect...) has nothing to do here
NODE="${XX_NODE_BINARY:-node}"
if [[ "${NODE}" == "~/"* ]]; then
  NODE="${HOME}/${NODE:2}"
fi

NODE_OPTIONS="" "${NODE}" "${DIR}/bash/transpile.mjs"
STATUS="${?}"

if [[ "${STATUS}" -ne 0 ]]; then
  echo "${0} error: generating templates failed with exit code >${STATUS}<" >&2
  exit "${STATUS}"
fi
