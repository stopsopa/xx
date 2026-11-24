# `--update` for a Rust binary released on GitHub

Instructions for an AI agent: how to add `<tool> --update` to a Rust command line tool, so it replaces itself with the latest GitHub release. Extracted from `stopsopa/xx` (`src/update.rs`, `.github/workflows/rust.yml`, `test/test025`), where it is implemented and tested.

Replace everywhere: `<tool>` = name of the binary, `<TOOL>` = prefix of its env vars, `<owner>/<repo>` = GitHub repository.

Section 9 covers the extra case where the tool is **two files** (a shell wrapper + the binary). Skip it for a plain binary.

## 1. What the user gets

```
<tool> --update            update to the latest release
<tool> --update <tag>      install the given release (also an older one), e.g. v0.1.0
<tool> --update --check    only say whether there is something newer, change nothing
```

Rules which must hold:

- **All or nothing.** After any failure the installed file is exactly what it was before. No half-downloaded or half-replaced binary, no temporary files left behind.
- **Nothing is trusted until verified**: sha256 from the release, then the new binary is really executed and has to report the expected version, all before the installed file is touched.
- **No new dependencies.** No HTTP or TLS crate, no JSON, no GitHub API, no token. Downloads go through `curl` (fallback `wget`), checksums through `sha256sum` (fallback `shasum -a 256`), started as subprocesses.
- **Testable offline.** The place releases come from can be replaced with a local directory.

## 2. What a release must contain

`--update` only works if every release has the same shape. Set this up first.

| File                  | Content                                                                                    |
| --------------------- | ------------------------------------------------------------------------------------------ |
| `<tool>-darwin-arm64` | one **bare binary** per platform, not an archive (nothing to unpack, nothing to depend on) |
| `<tool>-linux-x64`    |                                                                                            |
| `<tool>-linux-arm64`  |                                                                                            |
| `SHA256SUMS.txt`      | `shasum -a 256 <tool>-* > SHA256SUMS.txt`, lines `<sha256>  <file name>`                   |

- The names are a contract between the workflow and the binary (section 4). Add or remove platforms in both places.
- The tag is the version, and the binary must know its own tag (section 3).
- Releases must be published, not drafts: `/releases/latest` ignores drafts and prereleases.

Workflow, the relevant part (tag push → build matrix → one release job):

```yaml
# build job, per matrix target
- run: |
    if [ "${{ github.ref_type }}" = "tag" ]; then
      export <TOOL>_VERSION="${{ github.ref_name }}"
    fi
    cargo build --release --target ${{ matrix.target }}   # or: cross build ...
    mkdir -p dist
    cp target/${{ matrix.target }}/release/<tool> dist/${{ matrix.artifact_name }}

# release job, after downloading all artifacts to release-dist/
- run: |
    cd release-dist
    shasum -a 256 <tool>-* > SHA256SUMS.txt
- uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ github.ref_name }}
    draft: false
    files: release-dist/*
```

With `cross`, the version env var does not reach the container by itself. `Cross.toml`:

```toml
[build.env]
passthrough = ["<TOOL>_VERSION"]
```

## 3. The binary knows its version

The version is the pushed tag, injected at build time. Every other build is `dev`. Do not use the version from `Cargo.toml`: it would have to be bumped by hand and kept equal to the tag.

`build.rs`:

```rust
fn main() {
    println!("cargo:rerun-if-env-changed=<TOOL>_VERSION");
    let version = match std::env::var("<TOOL>_VERSION") {
        Ok(v) if !v.trim().is_empty() => v.trim().to_string(),
        _ => "dev".to_string(),
    };
    println!("cargo:rustc-env=<TOOL>_BUILD_VERSION={version}");
}
```

```rust
pub const VERSION: &str = env!("<TOOL>_BUILD_VERSION");
```

`<tool> --version` prints it in a fixed, exact form (`<tool> v1.2.3`), because the update compares that output as text (section 7).

A `dev` build refuses to update: it is not a release, there is nothing to compare with.

## 4. Which file is mine

Decided at compile time, not detected at runtime. The running binary is the best proof of what works on this machine, and no `uname` parsing is needed.

```rust
pub fn asset() -> Option<&'static str> {
    if cfg!(all(target_os = "macos", target_arch = "aarch64")) {
        Some("<tool>-darwin-arm64")
    } else if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
        Some("<tool>-linux-x64")
    } else if cfg!(all(target_os = "linux", target_arch = "aarch64")) {
        Some("<tool>-linux-arm64")
    } else {
        None // "there are no released binaries for this platform"
    }
}
```

## 5. Where releases come from, and what is the latest

```rust
pub const RELEASES: &str = "https://github.com/<owner>/<repo>/releases";
```

Env var `<TOOL>_RELEASES` replaces it (empty = default). It may be a URL or a **local directory** (expand a leading `~/`). Strip the trailing `/`. The local form exists for tests, and it also works for mirrors.

Layout, the same for both:

| What                | URL                                                         | Local directory                             |
| ------------------- | ----------------------------------------------------------- | ------------------------------------------- |
| latest tag          | `<releases>/latest` **redirects** to `<releases>/tag/<tag>` | file `<releases>/latest` containing the tag |
| a file of a release | `<releases>/download/<tag>/<file>`                          | the same path                               |

Reading the latest tag from the redirect means no API, so no rate limit, no token and no JSON parsing. Do not follow the redirect, only read where it points:

```bash
# curl prints the target of the redirect
curl -sS -o /dev/null -w '%{redirect_url}' <releases>/latest
# wget fallback: headers go to stderr, take the first "Location:" line
wget --max-redirect=0 -S -O /dev/null <releases>/latest
```

```rust
// "https://github.com/o/r/releases/tag/v0.1.0" -> "v0.1.0"
pub fn tag_from_redirect(location: &str) -> Option<String> {
    let tag = location.trim().rsplit_once("/tag/")?.1;
    let tag = tag.split(['?', '#', '/']).next()?;
    valid_tag(tag).then(|| tag.to_string())
}
```

When the repository has no release, GitHub redirects to `.../releases` (no `/tag/`): that is the "can't find out the latest release (no network? no release published yet?)" error, showing what was received.

The tag ends up in URLs and paths, also when the user typed it. Validate it in every case:

```rust
pub fn valid_tag(tag: &str) -> bool {
    !tag.is_empty()
        && tag.len() <= 64
        && !tag.starts_with(['.', '-'])
        && tag.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-' || b == b'_')
}
```

Downloading a file: `curl -fsSL <url>` (fallback `wget -q -O - <url>`), stdout captured as bytes, stdin `/dev/null`. `-f` matters: without it a 404 page is "downloaded" successfully. Treat empty content as an error. For a local source read the file.

## 6. Flow of `--update`

1. Parse arguments: nothing, `--check`, or one valid tag. Anything else prints the usage.
2. `VERSION == "dev"` → refuse.
3. `asset()` is `None` → refuse.
4. Tag = the requested one, or the latest (section 5).
5. Print `installed: <VERSION>` and `latest: <tag>` (or `requested: <tag>`).
6. `tag == VERSION` → `<tool> is up to date`, exit 0. Compare for equality only, not "newer than": that is what makes installing an older release possible, and no semver parsing is needed.
7. `--check` → print how to install it, exit 0.
8. Find the installed file: `std::env::current_exe()`, then `fs::canonicalize` (the tool may be started through a symlink; the real file is the one to replace). Print `files to replace:` with the path.
9. Ask for confirmation, default yes. An env var (`<TOOL>_CONFIRM=false`) skips the question; without a terminal and without that variable fail with an explanation instead of hanging.
10. Install (section 7).
11. Print `<tool> updated: <old> -> <tag>`.

Progress lines go to stderr or stdout consistently; every step which passed prints one line (`downloading ...`, `checksum ok: ...`, `test ok: ...`), so a failure report shows how far it got.

## 7. Replacing the file safely

The order is the whole point. Nothing installed is touched before step 4.

```
new = <installed>.new-<pid>      old = <installed>.old-<pid>      (same directory as the installed file)

1. download SHA256SUMS.txt, then the asset → write to `new`, chmod 755
2. sha256 of `new` must equal the line for the asset in SHA256SUMS.txt
3. run `new --version`: exit code 0 and output exactly "<tool> <tag>"
   ── until here nothing installed was touched ──
4. copy installed → `old`
5. rename `new` → installed
6. run installed `--version` again, the same check; on failure rename `old` → installed
7. always, success or failure: remove `new` and `old`
```

Why each detail:

- **Next to the installed file, not in `/tmp`**: `rename` is atomic only inside one filesystem. It also proves up front that the directory is writable ("the directory has to be writable for the update").
- **`rename`, never write into the installed file**: overwriting a running executable fails on Linux (`Text file busy`) and can get the process killed on macOS. Rename swaps the directory entry, the running process keeps its old file.
- **`<pid>` in the name**: two updates at once do not share temporary files.
- **Step 3 is not optional.** A checksum proves the file is the one from the release, not that it runs here (wrong libc, wrong architecture published under the right name, broken build). Running it does.
- **Step 6** repeats the test in the final location and is the only thing which can trigger a restore. If the restore itself fails, say so loudly and print where to install from by hand.
- **Cleanup in one place**: wrap the work in an inner function returning `Result`, and remove the temporary files in the outer one whatever the result was.

`SHA256SUMS.txt` parsing: split a line on whitespace, first part is the hash (64 hex characters, compare lowercase), second is the name with an optional leading `*`. A missing line for the asset is an error, never "skip verification".

Limit of the checksum, to state honestly in the docs: it comes from the same release as the binary, so it protects against a broken or truncated download, not against someone who controls the release.

## 8. Tests

Unit tests (pure functions): `valid_tag` (also `""`, `--check`, `../v1`, `..`, a tag with a space), `tag_from_redirect` (normal, with `?query`, the no-release redirect, empty), the `SHA256SUMS.txt` parser (uppercase hash, `*name`, too short hash, unknown name).

End-to-end, with releases faked in a local directory through `<TOOL>_RELEASES`. Build **two binaries with real versions** for it (`<TOOL>_VERSION=v9.9.8` and `v9.9.9`), because a `dev` build refuses to update. Every test gets its own temporary directory with its own "installed" copy.

```
releases/latest                          → "v9.9.9"
releases/download/v9.9.8/<asset>, SHA256SUMS.txt
releases/download/v9.9.9/<asset>, SHA256SUMS.txt
```

Cases, each asserting the exit code, the output and that the installed file is byte for byte what is expected:

- `--update --check` reports both versions and changes nothing.
- Answer "no" changes nothing.
- A release whose file does not match `SHA256SUMS.txt`: refused, nothing changed.
- A release whose checksum is fine but the binary reports another version (or does not run): caught by the test in step 3, nothing changed.
- A tag which does not exist: error, nothing changed.
- Real update: the installed file equals the released one, **no `.new-*` / `.old-*` files left**, `--version` prints the new tag.
- `--update <older tag>` installs the older release.
- Already the latest: `<tool> is up to date`.
- A `dev` build refuses.

The network path (redirect of `/releases/latest`) is not covered by these; check it once by hand after the first real release.

## 9. When the tool is two files (shell wrapper + binary)

`xx` is a sourced shell script `xx.sh` which calls the binary, and the wrapper accepts only a binary whose md5 was embedded into it by the build. Both files must then be replaced together. Differences from the above:

- The release also contains `xx.sh` (one file for all platforms, carrying the md5 of all binaries), listed in `SHA256SUMS.txt`.
- The binary can't know where the wrapper is. The wrapper passes its own path in an env var (`__XX_SH_PATH`, from `BASH_SOURCE`, in zsh `%x`). The path of the binary comes from the variable the wrapper uses to find it (`XX_BIN`), not from `current_exe()`. Calling `--update` on the binary directly is refused.
- Download and verify both, wrapper written with mode 644 and given the permissions of the installed one before the swap.
- The test of the pair is `source xx.sh --version` in a real shell (`/bin/bash`, plus zsh with `-f` when it is `$SHELL`) with the env var pointing to the binary. Expected output: both version lines. It proves that the wrapper loads, accepts the binary and the binary runs.
- Copy both aside, rename wrapper, rename binary. A failure of the first rename means nothing was replaced; a failure of the second rename or of the final test restores **both**.
- No shell restart is needed when the alias sources the wrapper on every call.
- An installation where the wrapper already rejects the binary can't update itself, on purpose: it would have to run a file it does not recognise. The user reinstalls by hand.

## 10. Checklist

- [ ] Release has bare binaries with fixed names + `SHA256SUMS.txt`; workflow passes the tag as `<TOOL>_VERSION` (also through `cross`).
- [ ] `build.rs` injects the version, default `dev`; `--version` prints exactly `<tool> <tag>`.
- [ ] `asset()` by `cfg!`, same names as in the workflow.
- [ ] `<TOOL>_RELEASES`: URL or local directory, same layout.
- [ ] Latest tag from the redirect of `/releases/latest`, tag validated.
- [ ] `curl -fsSL` / `wget`, `sha256sum` / `shasum -a 256`, no new crates.
- [ ] Download next to the installed file → checksum → run the new binary → copy aside → rename → run again → restore on failure → temporary files always removed.
- [ ] `--check`, `<tag>`, confirmation with a way to skip it, `dev` refuses.
- [ ] Unit tests + end-to-end tests against a local releases directory, including the failure cases.
- [ ] `--help` and the README describe `--update` and `<TOOL>_RELEASES`.
