// xx menu of this repository (https://github.com/stopsopa/xx), templates for other projects are in templates/
// TypeScript, ES module (export default). Executed by node directly (type stripping, node 22.18+).

// in order to run any xx command with custom export env var:
// (shopt -s expand_aliases; export ENVFILE=.env.ci; xx "docker up")

// 🚀 -
// ✅ -
// ⚙️  -
// 🗑️  -
// 🛑 -
// to call other xx commands from inside any xx command use:
//    shopt -s expand_aliases && source ~/.bashrc
// after that just do:
//   xx <command_name>
const S = "\\";
const GRAY = "\x1b[38;5;244m",
  BLACK = "\x1b[30m",
  RED = "\x1b[31m",
  GREEN = "\x1b[32m",
  YELLOW = "\x1b[33m",
  BLUE = "\x1b[34m",
  MAGENTA = "\x1b[35m",
  CYAN = "\x1b[36m",
  WHITE = "\x1b[37m",
  BOLD = "\x1b[1m",
  REVERSE = "\x1b[7m",
  RESET = "\x1b[0m";

const enter = `printf '\n${GREEN}Press Enter to continue (any other key exits)...${RESET}\n';old=$(stty -g);stty -icanon -echo
IFS= read -r -n1 k 2>/dev/null||IFS= read -r k;stty "$old"
[ -n "$k" ]&&exit 0;`;

const esc = `printf '\n${GREEN}Press any key to continue (Esc to exit)...${RESET}\n';old=$(stty -g);stty -icanon -echo
IFS= read -r -n1 k 2>/dev/null||IFS= read -r k;stty "$old"
[ "$k" = "$(printf '\\033')" ]&&exit 0;`;

type Command = {
  command: string;
  description?: string;
  source?: boolean;
  confirm?: boolean;
  order?: number;
};

type Commands = Record<string, Command>;

export default (setup: Commands): Commands => {
  return {
    help: {
      command: `
        
cat <<EEE

  🐙 GitHub: $(git ls-remote --get-url origin | awk '{\$1=\$1};1' | tr -d '\\n' | sed -E 's/git@github\\.com:([^/]+)\\/(.+)\\.git/https:\\/\\/github.com\\/\\1\\/\\2/g')

  docs:     README.md DEV.md PLAN.md
  releases: https://github.com/stopsopa/xx/releases
  pages:    https://stopsopa.github.io/xx/

EEE

      `,
      description: "Status of all things",
      source: false,
      confirm: false,
    },
    [`validateenv`]: {
      command: `
set -e      
/bin/bash validateenv.sh
`,
      description: `check if toolchain needed for development is installed`,
      confirm: false,
    },
    [`compile`]: {
      command: `
set -e      
/bin/bash compile.sh
`,
      description: `build binary to bin/<arch>/xx`,
      confirm: false,
    },
    [`test`]: {
      command: `
set -e
/bin/bash compile.sh
/bin/bash test.sh
`,
      description: `compile, then cargo test and all test/test*/test.sh`,
      confirm: false,
    },
    [`release notes preview`]: {
      command: `
set -e
/bin/bash compile.sh
TMP="$(mktemp -d)"
cp bin/*/xx "\${TMP}/xx-local-build"
/bin/bash bash/embed.sh "\${1:-v0.0.0}" "\${TMP}/xx.sh" "\${TMP}/xx-local-build"
(cd "\${TMP}" && shasum -a 256 xx-* xx.sh > SHA256SUMS.txt)
/bin/bash bash/release_notes.sh "\${1:-v0.0.0}" stopsopa/xx "\${TMP}"
`,
      description: `print body of github release, optional argument: tag (to see section from changelog.md)`,
      confirm: false,
    },
    [`publish`]: {
      command: `
set -e      
/bin/bash tag.sh
`,
      description: `create and push new tag, github actions will build and publish the release`,
      confirm: false,
    },
    [`style:check`]: {
      command: `
set -e
./node_modules/.bin/prettier --config prettier.config.cjs --check .
`,
      description: `prettier: check formatting of all files (the same check runs in CI)`,
      confirm: false,
    },
    [`style:fix`]: {
      command: `
set -e
./node_modules/.bin/prettier --config prettier.config.cjs --write .
`,
      description: `prettier: format all files in place`,
      confirm: false,
    },
    [`style:list`]: {
      command: `
set -e
./node_modules/.bin/prettier --config prettier.config.cjs --list-different .
`,
      description: `prettier: list files which are not formatted`,
      confirm: false,
    },

    ...setup,
  };
};
