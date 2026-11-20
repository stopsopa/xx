Test 021 verifies two things about picking and loading the config.

Priority: all twelve possible files exist at once and the one which wins is removed again and again. The order has to be `.git/xx.ts`, `.git/xx.js`, `.git/xx.mjs`, `.git/xx.cjs`, then the same four in the current directory, then the same four in home.

Module format against `"type"` in `package.json`:

- `"type": "module"`: `xx.js` and `xx.ts` are ES modules (also `.git/xx.js`, node finds `package.json` of the project from there), `xx.cjs` stays CommonJS, `module.exports` in `xx.js` fails with a clear error.
- `"type": "commonjs"`: `xx.js` is CommonJS, `xx.mjs` stays ES module.
- no `"type"`: `xx.js` works written either way (node detects it from the syntax), `xx.ts` works.
