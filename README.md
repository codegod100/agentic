# agentic

Nix packages for third-party tools that don't ship their own flakes.

## Layout

```
flake.nix              # flake entrypoint: exposes packages.* and apps.*
flake.lock
packages/
  vit/                 # one directory per package (callPackage style)
    default.nix
    package-lock.json  # only when we need a fixed/regenerated lock
    upstream.json      # how CI discovers and bumps this package
scripts/
  update-packages.sh   # version bump + hash/lock refresh
.github/workflows/
  update-packages.yml  # weekly cron + manual dispatch
```

Add a new package by creating `packages/<name>/default.nix` and wiring it in
`flake.nix` via `pkgs.callPackage ./packages/<name> { }`. For automated
updates, also add `packages/<name>/upstream.json` (see below).

## Packages

| Attr | Upstream | Install (non-Nix) |
|------|----------|-------------------|
| `vit` | [solpbc/vit](https://github.com/solpbc/vit) | `npm install -g vit` |
| `rook` | [solpbc/rook](https://github.com/solpbc/rook) | `npm install -g @solpbc/rook` |
| `spinel` | [matz/spinel](https://github.com/matz/spinel) | build from source (`make deps && make && make install`) |
| `boxd` | [boxd.sh](https://boxd.sh) / [docs](https://docs.boxd.sh/quickstart) | `curl -fsSL https://boxd.sh/downloads/install.sh \| sh` |
| `whetuu` | [yamafaktory/whetuu](https://github.com/yamafaktory/whetuu) | [install script](https://yamafaktory.github.io/whetuu/install.sh) / release tarballs |
| `pullrun` | [pullrun/pullrun](https://github.com/pullrun/pullrun) | `curl -fsSL https://github.com/pullrun/pullrun/raw/main/install.sh \| bash` |
| `zed-preview` | [zed-industries/zed](https://github.com/zed-industries/zed) (preview channel) | [official Linux installer](https://zed.dev/docs/linux) / `zed-linux-x86_64.tar.gz` |

## Usage

```bash
# build
nix build .#vit
nix build .#rook
nix build .#spinel
nix build .#boxd          # x86_64-linux / aarch64-linux / aarch64-darwin
nix build .#whetuu        # linux + darwin (all four systems)
nix build .#pullrun       # linux + darwin (all four systems)
nix build .#zed-preview   # x86_64-linux only

# run without installing
nix run .#vit -- --help
nix run .#rook -- --help
nix run .#spinel -- --help
nix run .#spin -- new myapp   # spin project tool (from the spinel package)
nix run .#boxd -- --help
nix run .#whetuu -- --version
nix run .#pullrun -- --version
nix run .#zed-preview -- --version

# install into your profile
nix profile install .#vit
nix profile install .#rook
nix profile install .#spinel
nix profile install .#boxd
nix profile install .#whetuu
nix profile install .#pullrun
nix profile install .#zed-preview
```

## Updating packages

### Automated (recommended)

A GitHub Action runs **every Monday** (and on manual dispatch) to:

1. Read each `packages/*/upstream.json`
2. Compare the packaged version to the latest upstream tag
3. Refresh source hashes, regenerate lockfiles when needed, recompute `npmDepsHash`
4. Verify `nix build .#<pkg>`
5. Open a PR on branch `chore/update-packages` if anything changed

```bash
# local dry-run: exit 1 if any package is behind upstream
./scripts/update-packages.sh --check

# apply updates locally (requires nix, curl, npm)
./scripts/update-packages.sh          # all packages
./scripts/update-packages.sh vit      # one package
```

### `upstream.json`

Supported types:

**npm-github** — tagged npm projects:

```json
{
  "type": "npm-github",
  "github": "owner/repo",
  "tag_prefix": "v"
}
```

`npm-github` packages are expected to use `buildNpmPackage` + `fetchFromGitHub`
with a `version` field and optional vendored `package-lock.json`.

**github-unstable** — projects without release tags (track branch tip):

```json
{
  "type": "github-unstable",
  "github": "owner/repo",
  "branch": "master"
}
```

Versions are `0-unstable-YYYY-MM-DD` with a pinned `rev` in `fetchFromGitHub`.
For spinel, the updater also re-reads `PRISM_VERSION` / `RBS_VERSION` from the
upstream Makefile and refreshes the vendored gem hashes when they change.

**github-release-binary** — prebuilt release assets (no source build):

Single-asset:

```json
{
  "type": "github-release-binary",
  "github": "owner/repo",
  "tag_prefix": "v",
  "tag_suffix": "-pre",
  "asset": "zed-linux-x86_64.tar.gz"
}
```

Multi-platform (`sources = { … }` block, like `url-manifest-binary`):

```json
{
  "type": "github-release-binary",
  "github": "owner/repo",
  "tag_prefix": "v",
  "platforms": {
    "x86_64-linux": "tool-v{version}-x86_64-linux-musl.tar.gz",
    "aarch64-linux": "tool-v{version}-aarch64-linux-musl.tar.gz",
    "x86_64-darwin": "tool-v{version}-x86_64-macos.tar.gz",
    "aarch64-darwin": "tool-v{version}-aarch64-macos.tar.gz"
  }
}
```

Tracks the newest non-draft GitHub release whose tag matches
`{tag_prefix}{semver}{tag_suffix}`. Single-asset mode refreshes one `fetchurl`
hash; multi-platform mode rewrites every `sources.<system>.{url,hash}`.
`{version}` in asset names is the bare version (no tag prefix). Used by
`zed-preview` (single) and `whetuu` (multi).

**url-manifest-binary** — prebuilt multi-platform binaries via a version
manifest URL (not GitHub releases):

```json
{
  "type": "url-manifest-binary",
  "manifest_url": "https://boxd.sh/downloads/cli/latest-{platform}.json",
  "platforms": {
    "x86_64-linux": "linux-amd64",
    "aarch64-linux": "linux-arm64",
    "aarch64-darwin": "darwin-arm64"
  }
}
```

`{platform}` is replaced per entry in `platforms`. Each manifest must expose
`version` + `url`; the updater prefetches every platform hash and rewrites the
`sources = { … }` block in `default.nix`. Used by `boxd`.

### Manual steps (vit / rook)

If you prefer to bump by hand (same flow for either npm-github package):

1. Bump `version` in `packages/<name>/default.nix`.
2. Prefetch the new source hash:
   ```bash
   nix-prefetch-url --unpack "https://github.com/solpbc/<name>/archive/refs/tags/vX.Y.Z.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. Regenerate a lockfile with resolved URLs when needed:
   ```bash
   tmp=$(mktemp -d) && cd "$tmp"
   curl -sL "https://github.com/solpbc/<name>/archive/refs/tags/vX.Y.Z.tar.gz" | tar -xz
   cd <name>-X.Y.Z
   rm -f package-lock.json bun.lock
   npm install --package-lock-only --ignore-scripts
   cp package-lock.json /path/to/this/repo/packages/<name>/package-lock.json
   ```
4. Set `npmDepsHash` to the all-zero fake hash, run `nix build .#<name>`, paste
   the hash nix prints as `got:`, rebuild.

Or just run `./scripts/update-packages.sh vit` / `./scripts/update-packages.sh rook`.

### Manual steps (spinel)

Spinel has no release tags yet, so the package pins a git commit as
`0-unstable-YYYY-MM-DD`. Prefer the updater:

```bash
./scripts/update-packages.sh spinel
```

By hand:

1. Bump `version`, `rev`, and the `fetchFromGitHub` `hash` in
   `packages/spinel/default.nix`.
2. If upstream changed `PRISM_VERSION` / `RBS_VERSION` in its Makefile, update
   `prismVersion` / `rbsVersion` and re-hash the gems:
   ```bash
   nix-prefetch-url "https://rubygems.org/gems/prism-X.Y.Z.gem"
   nix-prefetch-url "https://rubygems.org/gems/rbs-X.Y.Z.gem"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#spinel` and smoke-test `./result/bin/spinel -e 'puts 1'`.

### Manual steps (zed-preview)

`zed-preview` ships official Linux x86_64 preview binaries (tags `vX.Y.Z-pre`).
Prefer the updater:

```bash
./scripts/update-packages.sh zed-preview
```

By hand:

1. Bump `version` in `packages/zed-preview/default.nix` (e.g. `1.12.0-pre`).
2. Prefetch the tarball hash:
   ```bash
   nix-prefetch-url "https://github.com/zed-industries/zed/releases/download/vX.Y.Z-pre/zed-linux-x86_64.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. Paste the SRI hash into `fetchurl.hash`, then `nix build .#zed-preview` and
   smoke-test `./result/bin/zed-preview --version`.

### Manual steps (boxd)

`boxd` ships official static CLI binaries from [boxd.sh](https://boxd.sh)
(see [quickstart](https://docs.boxd.sh/quickstart)). Prefer the updater:

```bash
./scripts/update-packages.sh boxd
```

By hand:

1. Read the manifests and note the shared version:
   ```bash
   curl -fsSL https://boxd.sh/downloads/cli/latest-linux-amd64.json
   curl -fsSL https://boxd.sh/downloads/cli/latest-linux-arm64.json
   curl -fsSL https://boxd.sh/downloads/cli/latest-darwin-arm64.json
   ```
2. Bump `version` in `packages/boxd/default.nix`.
3. Prefetch each platform binary hash into the matching `sources.<system>.hash`:
   ```bash
   nix-prefetch-url "https://boxd.sh/downloads/cli/boxd-linux-amd64"
   nix-prefetch-url "https://boxd.sh/downloads/cli/boxd-linux-arm64"
   nix-prefetch-url "https://boxd.sh/downloads/cli/boxd-darwin-arm64"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
4. `nix build .#boxd` and smoke-test `./result/bin/boxd --version`.

### Manual steps (whetuu)

`whetuu` ships official multi-platform release tarballs (static musl on Linux).
Prefer the updater:

```bash
./scripts/update-packages.sh whetuu
```

By hand:

1. Bump `version` in `packages/whetuu/default.nix` (e.g. `0.1.5`).
2. Update each `sources.<system>.url` to the matching release asset and prefetch:
   ```bash
   nix-prefetch-url "https://github.com/yamafaktory/whetuu/releases/download/vX.Y.Z/whetuu-vX.Y.Z-x86_64-linux-musl.tar.gz"
   nix-prefetch-url "https://github.com/yamafaktory/whetuu/releases/download/vX.Y.Z/whetuu-vX.Y.Z-aarch64-linux-musl.tar.gz"
   nix-prefetch-url "https://github.com/yamafaktory/whetuu/releases/download/vX.Y.Z/whetuu-vX.Y.Z-x86_64-macos.tar.gz"
   nix-prefetch-url "https://github.com/yamafaktory/whetuu/releases/download/vX.Y.Z/whetuu-vX.Y.Z-aarch64-macos.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#whetuu` and smoke-test `./result/bin/whetuu --version`.

### Manual steps (pullrun)

`pullrun` ships official multi-platform release tarballs (CLI + runtime, static).
Prefer the updater:

```bash
./scripts/update-packages.sh pullrun
```

By hand:

1. Bump `version` in `packages/pullrun/default.nix` (e.g. `0.6.7`).
2. Update each `sources.<system>.url` to the matching release asset and prefetch:
   ```bash
   nix-prefetch-url "https://github.com/pullrun/pullrun/releases/download/vX.Y.Z/pullrun-X.Y.Z-linux-amd64.tar.gz"
   nix-prefetch-url "https://github.com/pullrun/pullrun/releases/download/vX.Y.Z/pullrun-X.Y.Z-linux-arm64.tar.gz"
   nix-prefetch-url "https://github.com/pullrun/pullrun/releases/download/vX.Y.Z/pullrun-X.Y.Z-darwin-amd64.tar.gz"
   nix-prefetch-url "https://github.com/pullrun/pullrun/releases/download/vX.Y.Z/pullrun-X.Y.Z-darwin-arm64.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#pullrun` and smoke-test `./result/bin/pullrun --version` and
   `./result/bin/pullrun-runtime --version`.
