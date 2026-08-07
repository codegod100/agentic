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
  ci.yml               # build on nixbuild.net; push to Cachix on merge
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
| `gleam-preview` | [gleam-lang/gleam](https://github.com/gleam-lang/gleam) (prereleases) | [install docs](https://gleam.run/getting-started/installing/) / release tarballs |
| `zed-preview` | [zed-industries/zed](https://github.com/zed-industries/zed) (preview channel) | [official Linux installer](https://zed.dev/docs/linux) / `zed-linux-x86_64.tar.gz` |
| `halloy` | [squidowl/halloy](https://github.com/squidowl/halloy) | [GitHub releases](https://github.com/squidowl/halloy/releases) / `halloy-*-x86_64-linux.tar.gz` |
| `pulp` | [cheywood/Pulp](https://gitlab.gnome.org/cheywood/Pulp) | [Flathub](https://flathub.org/apps/details/org.gnome.gitlab.cheywood.Pulp) |
| `mimic` | [ArijanJ/Mimic](https://github.com/ArijanJ/Mimic) | [Flathub](https://flathub.org/apps/io.github.arijanj.Mimic) |
| `portfolio` | [tchx84/Portfolio](https://github.com/tchx84/Portfolio) | [Flathub](https://flathub.org/apps/details/dev.tchx84.Portfolio) |
| `eyg` | [CrowdHailer/eyg-lang](https://github.com/CrowdHailer/eyg-lang) | `curl -fsSL https://eyg.run/install \| bash` |
| `rsvelte` | [baseballyama/rsvelte](https://github.com/baseballyama/rsvelte) (`@rsvelte/fmt`, `@rsvelte/lint`, `@rsvelte/svelte-check`) | `npm install -g @rsvelte/fmt @rsvelte/lint @rsvelte/svelte-check` |
| `prime-agent` | [PrimeIntellect-ai/prime-agent](https://github.com/PrimeIntellect-ai/prime-agent) | `curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh \| sh` |
| `lore` | [EpicGames/lore](https://github.com/EpicGames/lore) | [install script](https://raw.githubusercontent.com/EpicGames/lore/main/scripts/install.sh) / release tarballs |
| `loreserver` | [EpicGames/lore](https://github.com/EpicGames/lore) | [install script](https://raw.githubusercontent.com/EpicGames/lore/main/scripts/install.sh) (`--server` / `--demo`) / release tarballs |
| `celld` | [denoland/celld](https://github.com/denoland/celld) | `curl -fsSL https://celld.dev/install.sh \| sh` |
## Binary cache (Cachix)

CI compiles every package on [nixbuild.net](https://nixbuild.net) (GHA only
evaluates/orchestrates), then pushes results to the public
[`codegod100`](https://app.cachix.org/cache/codegod100) Cachix cache on merges
to `main`. The flake advertises the cache via `nixConfig`; accept the
substituter when prompted, or configure it once:

```bash
# nix.conf / NixOS: trusted-substituters + trusted-public-keys
extra-substituters = https://codegod100.cachix.org
extra-trusted-public-keys = codegod100.cachix.org-1:LZFL5VrR644WUjleS3bLbVeOdzlXqzKznQWvD5MVthA=
```

CI secrets:
- `NIXBUILD_TOKEN` (required) — remote builds on nixbuild.net
- `CACHIX_AUTH_TOKEN` (required on `main`) — write token for Cachix pushes

Both can instead be loaded from OpenBao `secret/data/ai-api-keys` when
`OPENBAO_TOKEN` / `BAO_TOKEN` is set as a GitHub Actions secret.

## Usage

```bash
# build
nix build .#vit
nix build .#rook
nix build .#spinel
nix build .#boxd          # x86_64-linux / aarch64-linux / aarch64-darwin
nix build .#whetuu        # linux + darwin (all four systems)
nix build .#pullrun       # linux + darwin (all four systems)
nix build .#gleam-preview # linux + darwin (all four systems)
nix build .#zed-preview   # x86_64-linux only
nix build .#halloy        # x86_64-linux only
nix build .#pulp          # linux only (GNOME/GTK4)
nix build .#mimic         # linux only (GTK4/libadwaita)
nix build .#portfolio     # linux only (GTK4/libadwaita file manager)
nix build .#eyg           # linux + darwin (all four systems)
nix build .#rsvelte       # linux + darwin; bins: rsvelte-fmt, rsvelte-lint, rsvelte-check
nix build .#prime-agent   # linux + darwin (Node >= 22.8; release npm pack + Nix kernel Python)
nix build .#lore          # x86_64-linux / aarch64-linux / aarch64-darwin
nix build .#loreserver    # same platforms as lore
nix build .#celld         # x86_64-linux / aarch64-linux / aarch64-darwin
# run without installing
nix run .#vit -- --help
nix run .#rook -- --help
nix run .#spinel -- --help
nix run .#spin -- new myapp   # spin project tool (from the spinel package)
nix run .#boxd -- --help
nix run .#whetuu -- --version
nix run .#pullrun -- --version
nix run .#gleam-preview -- --version
nix run .#zed-preview -- --version
nix run .#halloy -- --version
nix run .#pulp
nix run .#mimic
nix run .#portfolio
nix run .#eyg -- --version
nix run .#eyg -- eval -c '!int_add(1, 1)'
nix run .#rsvelte-fmt -- --version
nix run .#rsvelte-lint -- --version
nix run .#rsvelte-check -- --help   # apps from the rsvelte package
nix run .#prime-agent -- --version
nix run .#lore -- --version
nix run .#loreserver -- --version
nix run .#celld -- --version

# install into your profile
nix profile install .#vit
nix profile install .#rook
nix profile install .#spinel
nix profile install .#boxd
nix profile install .#whetuu
nix profile install .#pullrun
nix profile install .#gleam-preview
nix profile install .#zed-preview
nix profile install .#halloy
nix profile install .#pulp
nix profile install .#mimic
nix profile install .#portfolio
nix profile install .#eyg
nix profile install .#rsvelte       # installs fmt + lint + check
nix profile install .#prime-agent
nix profile install .#lore
nix profile install .#loreserver
nix profile install .#celld
```

Ladybird lives in the [`codegod100/ladybird`](https://github.com/codegod100/ladybird)
fork (Nix flake + in-tree OpenBao passkeys/passwords):
`nix run github:codegod100/ladybird`.

## Updating packages

### Automated (recommended)

A GitHub Action runs **every Monday** (and on manual dispatch) to:

1. Read each `packages/*/upstream.json`
2. Compare the packaged version to the latest upstream tag
3. Refresh source hashes, regenerate lockfiles when needed, recompute `npmDepsHash`
4. Verify `nix build .#<pkg>`
5. Open a PR on branch `chore/update-packages` if anything changed

```bash
# preferred: flake app (wraps scripts/update-packages.sh; run from this checkout)
nix run .#update -- --check   # dry-run: exit 1 if any package is behind
nix run .#update              # bump all packages from upstream
nix run .#update -- vit       # one package

# same script directly
./scripts/update-packages.sh --check
./scripts/update-packages.sh
./scripts/update-packages.sh vit
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

**gitlab-tag** — tagged source packages on GitLab (including GNOME GitLab):

```json
{
  "type": "gitlab-tag",
  "domain": "gitlab.gnome.org",
  "gitlab": "owner/repo",
  "tag_prefix": ""
}
```

Tracks the newest tag matching `{tag_prefix}` + numeric version (CalVer like
`2026.4` or semver). Refreshes `version` and the `fetchFromGitLab` `hash`.
Used by `pulp`.

**github-tag** — tagged source packages on GitHub (no npm lockfile):

```json
{
  "type": "github-tag",
  "github": "owner/repo",
  "tag_prefix": "v"
}
```

Tracks the newest tag matching `{tag_prefix}` + semver. Refreshes `version`
and the `fetchFromGitHub` `hash`. Used by `mimic`.

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
`{tag_prefix}{version}{tag_suffix}` (semver or CalVer with 2+ numeric
components). Set `"tag_prefix": ""` for unprefixed tags (e.g. Halloy `2026.8`).
Set `"tag_prerelease": true` to match any prerelease tag (`vX.Y.Z-rc1`,
`vX.Y.Z-beta`, …) instead of a fixed suffix. Single-asset mode refreshes one
`fetchurl` hash; multi-platform mode rewrites every `sources.<system>.{url,hash}`.
`{version}` in asset names is the bare version (no tag prefix). Used by
`zed-preview` (single), `whetuu` / `gleam-preview` / `pullrun` / `halloy`
(multi; halloy is x86_64-linux only), `lore` / `loreserver` / `celld` (multi;
no darwin-x86_64).

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

**npm-registry-binary** — prebuilt multi-platform binaries published to npm.

Single-tool form:

```json
{
  "type": "npm-registry-binary",
  "npm": "@scope/name",
  "platforms": {
    "x86_64-linux": "@scope/name-linux-x64-gnu",
    "aarch64-linux": "@scope/name-linux-arm64-gnu",
    "x86_64-darwin": "@scope/name-darwin-x64",
    "aarch64-darwin": "@scope/name-darwin-arm64"
  }
}
```

Tracks `dist-tags.latest` for the `npm` package, then rewrites every
`sources.<system>.{url,hash}` from the matching platform package tarball
(`https://registry.npmjs.org/@scope/pkg/-/pkg-<version>.tgz`).

Multi-tool form (one Nix package, independently versioned CLIs) — used by
`rsvelte`:

```json
{
  "type": "npm-registry-binary",
  "tools": [
    {
      "pname": "rsvelte-fmt",
      "npm": "@rsvelte/fmt",
      "platforms": {
        "x86_64-linux": "@rsvelte/fmt-linux-x64-gnu",
        "aarch64-linux": "@rsvelte/fmt-linux-arm64-gnu",
        "x86_64-darwin": "@rsvelte/fmt-darwin-x64",
        "aarch64-darwin": "@rsvelte/fmt-darwin-arm64"
      }
    }
  ]
}
```

Each `tools[]` entry tracks its own `dist-tags.latest` and refreshes the
`sources = { … }` block under the matching `pname = "…"; version = "…";` in
`default.nix`.

**github-release-npm** — prebuilt npm pack published as a GitHub Release asset:

```json
{
  "type": "github-release-npm",
  "github": "PrimeIntellect-ai/prime-agent",
  "tag_prefix": "v",
  "asset": "prime-agent-{version}.tgz"
}
```

Tracks the newest semver tag, refreshes the `fetchurl` hash for the release
tarball, regenerates `package-lock.json` from that pack (URL deps kept as
upstream publishes them), and recomputes `npmDepsHash`. Used by `prime-agent`.

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

### Manual steps (gleam-preview)

`gleam-preview` ships official multi-platform prerelease binaries (tags
`vX.Y.Z-rcN`, etc.). The binary is installed as `gleam-preview` so it can
coexist with nixpkgs `gleam`. Prefer the updater:

```bash
./scripts/update-packages.sh gleam-preview
```

By hand:

1. Bump `version` in `packages/gleam-preview/default.nix` (e.g. `1.18.0-rc1`).
2. Update each `sources.<system>.url` to the matching release asset and prefetch:
   ```bash
   nix-prefetch-url "https://github.com/gleam-lang/gleam/releases/download/vX.Y.Z-rcN/gleam-vX.Y.Z-rcN-x86_64-unknown-linux-musl.tar.gz"
   nix-prefetch-url "https://github.com/gleam-lang/gleam/releases/download/vX.Y.Z-rcN/gleam-vX.Y.Z-rcN-aarch64-unknown-linux-musl.tar.gz"
   nix-prefetch-url "https://github.com/gleam-lang/gleam/releases/download/vX.Y.Z-rcN/gleam-vX.Y.Z-rcN-x86_64-apple-darwin.tar.gz"
   nix-prefetch-url "https://github.com/gleam-lang/gleam/releases/download/vX.Y.Z-rcN/gleam-vX.Y.Z-rcN-aarch64-apple-darwin.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#gleam-preview` and smoke-test `./result/bin/gleam-preview --version`.

### Manual steps (halloy)

`halloy` ships an official Linux x86_64 release tarball (IRC client). Prefer the
updater:

```bash
./scripts/update-packages.sh halloy
```

By hand:

1. Bump `version` in `packages/halloy/default.nix` (e.g. `2026.8`).
2. Update `sources.x86_64-linux.url` and prefetch:
   ```bash
   nix-prefetch-url "https://github.com/squidowl/halloy/releases/download/X.Y/halloy-X.Y-x86_64-linux.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#halloy` and smoke-test `./result/bin/halloy --version`.

### Manual steps (pulp)

`pulp` is a GNOME RSS reader built from source (Meson + Python + GTK4). Prefer
the updater:

```bash
./scripts/update-packages.sh pulp
```

By hand:

1. Bump `version` in `packages/pulp/default.nix` (e.g. `2026.4`).
2. Prefetch the source hash:
   ```bash
   nix-prefetch-url --unpack "https://gitlab.gnome.org/cheywood/Pulp/-/archive/X.Y/Pulp-X.Y.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. Paste the SRI hash into `fetchFromGitLab.hash`, then `nix build .#pulp`.

### Manual steps (portfolio)

`portfolio` is a minimalist GTK4 file manager built from source (Meson + Python).
Prefer the updater:

```bash
./scripts/update-packages.sh portfolio
```

By hand:

1. Bump `version` in `packages/portfolio/default.nix` (e.g. `1.0.3`).
2. Prefetch the source hash:
   ```bash
   nix-prefetch-url --unpack "https://github.com/tchx84/Portfolio/archive/refs/tags/vX.Y.Z.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. Paste the SRI hash into `fetchFromGitHub.hash`, then `nix build .#portfolio`.

### Manual steps (prime-agent)

`prime-agent` ships a prebuilt npm pack on GitHub Releases (`prime-agent-X.Y.Z.tgz`).
The flake wraps the CLI with `PRIME_AGENT_KERNEL_PYTHON` pointing at a Nix-built
Python 3.12 env (ipykernel, `dist/prime-agent-runtime` from the same pack, dill,
and upstream's default RLM packages) so the IPython kernel does not need `uv` or
network on first use. Prefer the updater:

```bash
./scripts/update-packages.sh prime-agent
```

By hand:

1. Bump `version` in `packages/prime-agent/default.nix`.
2. Prefetch the release tarball hash:
   ```bash
   nix-prefetch-url "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/vX.Y.Z/prime-agent-X.Y.Z.tgz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. Regenerate `packages/prime-agent/package-lock.json` from that pack:
   ```bash
   tmp=$(mktemp -d) && cd "$tmp"
   curl -fsSL "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/vX.Y.Z/prime-agent-X.Y.Z.tgz" | tar -xz
   cd package
   npm install --package-lock-only --ignore-scripts
   cp package-lock.json /path/to/this/repo/packages/prime-agent/package-lock.json
   ```
4. Set `npmDepsHash` to the all-zero fake hash, run `nix build .#prime-agent`,
   paste the hash nix prints as `got:`, rebuild, then smoke-test
   `./result/bin/prime-agent --version` and
   `$(nix build .#prime-agent.kernelPython --print-out-paths)/bin/python -c 'import ipykernel, rlm'`.

### Manual steps (rsvelte)

`rsvelte` ships the official prebuilt fmt / lint / check CLIs via npm platform
packages from [baseballyama/rsvelte](https://github.com/baseballyama/rsvelte).
Prefer the updater (bumps each tool independently):

```bash
./scripts/update-packages.sh rsvelte
```

By hand:

1. Bump each tool `version` under `packages/rsvelte/default.nix` to match npm
   (`@rsvelte/fmt`, `@rsvelte/lint`, `@rsvelte/svelte-check`).
2. Update each tool's `sources.<system>.url` and prefetch:
   ```bash
   nix-prefetch-url "https://registry.npmjs.org/@rsvelte/fmt-linux-x64-gnu/-/fmt-linux-x64-gnu-X.Y.Z.tgz"
   nix-prefetch-url "https://registry.npmjs.org/@rsvelte/lint-linux-x64-gnu/-/lint-linux-x64-gnu-X.Y.Z.tgz"
   nix-prefetch-url "https://registry.npmjs.org/@rsvelte/svelte-check-linux-x64-gnu/-/svelte-check-linux-x64-gnu-X.Y.Z.tgz"
   # …and the arm64 / darwin variants
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#rsvelte` and smoke-test `./result/bin/rsvelte-fmt --version`,
   `./result/bin/rsvelte-lint --version`, and
   `./result/bin/rsvelte-check --help`.

### Manual steps (lore / loreserver)

`lore` and `loreserver` ship separate multi-platform release tarballs (dynamic
glibc on Linux; no darwin-x86_64; aarch64-linux is Neoverse/Graviton only).
Prefer the updater:

```bash
./scripts/update-packages.sh lore
./scripts/update-packages.sh loreserver
```

By hand:

1. Bump `version` in `packages/lore/default.nix` and
   `packages/loreserver/default.nix` (e.g. `0.8.5`).
2. Update each `sources.<system>.url` to the matching release asset and prefetch:
   ```bash
   # lore CLI
   nix-prefetch-url "https://github.com/EpicGames/lore/releases/download/vX.Y.Z/lore-vX.Y.Z-x86_64-unknown-linux-gnu.tar.gz"
   nix-prefetch-url "https://github.com/EpicGames/lore/releases/download/vX.Y.Z/lore-vX.Y.Z-aarch64-unknown-linux-gnu-neoverse-512tvb.tar.gz"
   nix-prefetch-url "https://github.com/EpicGames/lore/releases/download/vX.Y.Z/lore-vX.Y.Z-aarch64-apple-darwin.tar.gz"
   # loreserver
   nix-prefetch-url "https://github.com/EpicGames/lore/releases/download/vX.Y.Z/loreserver-vX.Y.Z-x86_64-unknown-linux-gnu.tar.gz"
   nix-prefetch-url "https://github.com/EpicGames/lore/releases/download/vX.Y.Z/loreserver-vX.Y.Z-aarch64-unknown-linux-gnu-neoverse-512tvb.tar.gz"
   nix-prefetch-url "https://github.com/EpicGames/lore/releases/download/vX.Y.Z/loreserver-vX.Y.Z-aarch64-apple-darwin.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#lore` / `nix build .#loreserver` and smoke-test
   `./result/bin/lore --version` / `./result/bin/loreserver --version`.

### Manual steps (celld)

`celld` ships official multi-platform release binaries as gzip-compressed
executables (dynamic glibc on Linux; no darwin-x86_64). Prefer the updater:

```bash
./scripts/update-packages.sh celld
```

By hand:

1. Bump `version` in `packages/celld/default.nix` (e.g. `0.1.0`).
2. Update each `sources.<system>.url` to the matching release asset and prefetch:
   ```bash
   nix-prefetch-url "https://github.com/denoland/celld/releases/download/vX.Y.Z/celld-x86_64-unknown-linux-gnu.gz"
   nix-prefetch-url "https://github.com/denoland/celld/releases/download/vX.Y.Z/celld-aarch64-unknown-linux-gnu.gz"
   nix-prefetch-url "https://github.com/denoland/celld/releases/download/vX.Y.Z/celld-aarch64-apple-darwin.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. `nix build .#celld` and smoke-test `./result/bin/celld --version`.
