/**
 * Generates templates/xx.js, templates/xx.mjs and templates/xx.cjs from templates/xx.ts
 * Executed by transpile.sh, see the description there.
 *
 *   node bash/transpile.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { transform } from "esbuild";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dir = path.join(root, "templates");
const sourceFile = path.join(dir, "xx.ts");

const fail = (message) => {
  process.stderr.write(`transpile.mjs error: ${message}\n`);
  process.exit(1);
};

/**
 * What is said at the top of each generated file, instead of what xx.ts says about itself
 */
const flavours = {
  js: {
    format: "esm",
    notes: [
      `ES module (export default). Works when nearest package.json has "type": "module" or no "type" at all.`,
      `If it says "type": "commonjs" replace "export default" with "module.exports =" (or use xx.mjs)`,
    ],
  },
  mjs: {
    format: "esm",
    notes: [`ES module (export default), always, no matter what "type" says in package.json`],
  },
  cjs: {
    format: "cjs",
    notes: [`CommonJS (module.exports), always, no matter what "type" says in package.json`],
  },
};

const source = fs.readFileSync(sourceFile, "utf8");

/**
 * esbuild removes comments, so the comment at the top of xx.ts is carried over by hand:
 *   first paragraph  - describes xx.ts itself, replaced with description of generated flavour
 *   next paragraphs  - general hints, copied as they are
 * The block ends with first line which is not a comment and not empty.
 */
const lines = source.split("\n");
let end = 0;
while (end < lines.length && (lines[end].startsWith("//") || lines[end].trim() === "")) {
  end += 1;
}
const leading = lines.slice(0, end);
const firstBlank = leading.findIndex((l) => l.trim() === "");
if (end === 0 || firstBlank < 1) {
  fail(`>${sourceFile}< has to start with a comment paragraph (describing the file) followed by an empty line`);
}
const hints = leading
  .slice(firstBlank + 1)
  .join("\n")
  .trim();

function header(ext, notes) {
  return [
    `// template of xx config, flavour: xx.${ext}`,
    ...notes.map((n) => `// ${n}`),
    `// project      : https://github.com/stopsopa/xx`,
    `// generated    : from https://github.com/stopsopa/xx/blob/main/templates/xx.ts (types removed, comments in the code too)`,
    `// to get it    : xx --init ${ext}`,
    ``,
    ...(hints ? [hints, ``] : []),
  ].join("\n");
}

// types are removed, the code stays as modern as it is written
const { code } = await transform(source, {
  loader: "ts",
  format: "esm",
  target: "esnext",
  sourcefile: "xx.ts",
});

// esbuild turns "export default <expression>" into this pair
const DECLARATION = "var xx_default = ";
const EXPORT = /\nexport \{\n\s*xx_default as default\n\};\n*$/;

if (code.split(DECLARATION).length !== 2 || !EXPORT.test(code)) {
  fail(
    `unexpected output of esbuild: expected exactly one >${DECLARATION}< and >export { xx_default as default };< at the end. ` +
      `>${sourceFile}< has to have exactly one export: export default <function>`,
  );
}

const body = code.replace(EXPORT, "\n");

const bodies = {
  esm: body.replace(DECLARATION, "export default "),
  cjs: body.replace(DECLARATION, "module.exports = "),
};

const generated = [];

for (const [ext, { format, notes }] of Object.entries(flavours)) {
  const file = path.join(dir, `xx.${ext}`);
  fs.writeFileSync(file, header(ext, notes) + bodies[format]);
  generated.push(file);
}

/**
 * Proof that nothing was lost: every generated file is loaded the way xx loads it
 * and has to return exactly what xx.ts returns
 */
const ctx = { args: ["a", "b c"], cwd: "/some/cwd", configPath: "/some/config/xx", configDir: "/some/config" };

async function load(file) {
  // .js is loaded from a copy named .mjs: this repository says "type": "module", but the file
  // has to be checked on its own, the name of the copy says what it is expected to be
  let target = file;
  if (file.endsWith(".js")) {
    target = path.join(fs.mkdtempSync(path.join(fs.realpathSync(dir), ".check-")), "xx.mjs");
    fs.copyFileSync(file, target);
  }
  try {
    const mod = await import(pathToFileURL(target).href);
    if (typeof mod.default !== "function") {
      fail(`default export of >${file}< is not a function`);
    }
    return JSON.stringify(await mod.default({ extra: { command: "echo extra" } }, ctx));
  } finally {
    if (target !== file) {
      fs.rmSync(path.dirname(target), { recursive: true });
    }
  }
}

const expected = await load(sourceFile);

if (Object.keys(JSON.parse(expected)).length < 2) {
  fail(`>${sourceFile}< returned less than 2 commands, something is wrong with it`);
}

for (const file of generated) {
  if ((await load(file)) !== expected) {
    fail(`>${file}< returns something else than >${sourceFile}<`);
  }
}

// stdout: only paths of generated files
process.stdout.write(generated.join("\n") + "\n");
