Test 016 verifies `xx --init [ts|js|mjs|cjs]` and `xx --esm [path]`. Nothing is downloaded from the internet: `XX_INIT_CONFIG` points to a local json which lists local paths of the templates from this repository (that is what local paths in `XX_INIT_CONFIG` are for).

- `--init` without kind creates `xx.ts`; without `.git` in the current directory, with `.git` in `.git/`.
- every kind creates exactly its template, and the created file loads (`xx --list`).
- existing file is never overwritten, unknown kind is an error.
- `--esm` creates the ts template in the default place, in given directory (`<dir>/xx.ts`) or as given file.
- paths in the json can be absolute, `file://` or relative to the json; `XX_INIT_CONFIG` itself can be relative to the current directory.
- errors: kind missing in the json, broken json, missing json, missing template. Nothing is left behind.
- `init.json` published in the repository (the default `XX_INIT_CONFIG`) lists all four templates and the files exist.

Downloading through http (curl / wget) is not covered by tests.
