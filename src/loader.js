/**
 * Loader executed by the xx binary:
 *
 *   node -e <this file> <absolute path to xx.cjs> <context as json>
 *
 * Loads the config, calls exported function and prints list of commands
 * as json array of [key, value] pairs between two markers on stdout.
 *
 * Array (not object) is used on purpose: it keeps the order of keys exactly as node sees it.
 *
 * Anything the config itself prints to stdout is redirected to stderr,
 * so it can't corrupt the json.
 */
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const BEGIN = "<<<XX_JSON_BEGIN>>>";
const END = "<<<XX_JSON_END>>>";

const [configPath, ctxJson] = process.argv.slice(1);

const fail = (m) => {
  process.stderr.write(`xx error: ${m}\n`);
  process.exit(1);
};

// from now on stdout belongs to the json only
process.stdout.write = process.stderr.write.bind(process.stderr);

function isObject(o) {
  return Object.prototype.toString.call(o) === "[object Object]";
}

(async function () {
  const ctx = JSON.parse(ctxJson || "{}");

  let mod;

  if (/\.cjs$/.test(configPath)) {
    mod = require(path.resolve(configPath));
  } else {
    mod = await import(pathToFileURL(path.resolve(configPath)).href);
  }

  // module.exports = fn (cjs) or export default fn (mjs)
  let fn = mod;
  if (typeof fn !== "function" && mod && typeof mod.default === "function") {
    fn = mod.default;
  }

  if (typeof fn !== "function") {
    fail(`default export is not a function in module >${configPath}<`);
  }

  // first argument stays {} for backward compatibility ("...setup" at the end of the template)
  const setup = await fn({}, ctx);

  if (!isObject(setup)) {
    fail(`object is not returned from default function exported from >${configPath}<`);
  }

  const entries = Object.entries(setup).map(([key, value]) => {
    if (!isObject(value)) {
      fail(`value for key >${key}< in >${configPath}< is not an object`);
    }
    return [
      key,
      {
        command: value.command,
        description: value.description,
        confirm: value.confirm,
        source: value.source,
        order: value.order,
      },
    ];
  });

  fs.writeSync(1, `\n${BEGIN}${JSON.stringify(entries)}${END}\n`);
})().catch((e) => {
  process.stderr.write(`xx error: loading >${configPath}< failed:\n${(e && e.stack) || e}\n`);
  process.exit(1);
});
