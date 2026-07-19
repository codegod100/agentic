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
```

Add a new package by creating `packages/<name>/default.nix` and wiring it in
`flake.nix` via `pkgs.callPackage ./packages/<name> { }`.

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

## Updating `vit`

1. Bump `version` / `rev` in `packages/vit/default.nix`.
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
4. Set `npmDepsHash = lib.fakeHash;`, run `nix build .#vit`, paste the hash
   nix prints as `got:`, rebuild.
