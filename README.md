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

## Usage

```bash
# build
nix build .#vit

# run without installing
nix run .#vit -- --help

# install into your profile
nix profile install .#vit
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

Currently supported type:

```json
{
  "type": "npm-github",
  "github": "owner/repo",
  "tag_prefix": "v"
}
```

`npm-github` packages are expected to use `buildNpmPackage` + `fetchFromGitHub`
with a `version` field and optional vendored `package-lock.json`.

### Manual steps (vit)

If you prefer to bump by hand:

1. Bump `version` in `packages/vit/default.nix`.
2. Prefetch the new source hash:
   ```bash
   nix-prefetch-url --unpack "https://github.com/solpbc/vit/archive/refs/tags/vX.Y.Z.tar.gz"
   nix hash convert --hash-algo sha256 --to sri <base32>
   ```
3. Regenerate a lockfile with resolved URLs (upstream's is often missing them):
   ```bash
   tmp=$(mktemp -d) && cd "$tmp"
   curl -sL "https://github.com/solpbc/vit/archive/refs/tags/vX.Y.Z.tar.gz" | tar -xz
   cd vit-X.Y.Z
   rm -f package-lock.json bun.lock
   npm install --package-lock-only --ignore-scripts
   cp package-lock.json /path/to/this/repo/packages/vit/package-lock.json
   ```
4. Set `npmDepsHash` to the all-zero fake hash, run `nix build .#vit`, paste the
   hash nix prints as `got:`, rebuild.

Or just run `./scripts/update-packages.sh vit`.
