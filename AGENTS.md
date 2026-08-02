# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **Nix flake** that packages third-party tools (`packages.*`) and
exposes runnable apps (`apps.*`). There is no server to run and no test suite;
the "application" is the flake itself — you build packages with `nix build` and
run them with `nix run`. See `README.md` for the full package list and the
canonical build/run/update commands.

### Nix setup on this VM (already done by the update script)

- Nix is installed **single-user, no daemon** (the VM init is `tini`, not
  systemd, so a multi-user daemon install is not used). The store lives in
  `/nix` and is owned by the `ubuntu` user.
- Flakes are enabled via `~/.config/nix/nix.conf`
  (`experimental-features = nix-command flakes`, `accept-flake-config = true`).
  `accept-flake-config` matters: it auto-accepts the flake's public Cachix
  substituter (`codegod100.cachix.org`), so most packages **download from the
  binary cache instead of building from source**.
- If `nix` is not on `PATH` in a fresh shell, source it first:
  `. "$HOME/.nix-profile/etc/profile.d/nix.sh"` (this is also appended to
  `~/.bashrc`, so interactive bash shells pick it up automatically).

### Build / run / lint / check

- Build a package: `nix build .#<pkg>` (e.g. `nix build .#vit`).
- Run a package: `nix run .#<pkg> -- <args>` (e.g. `nix run .#eyg -- eval -c '!int_add(1, 1)'`).
- Flake validation (fast, no builds): `nix flake check --no-build`.
- Version-drift check (the repo's "lint"): `./scripts/update-packages.sh --check`
  (exits `1` when any package is behind upstream — that is expected, not a
  failure of your setup). It needs `curl`, `nix`, `nix-prefetch-url`, `python3`,
  and `npm`, all present on the VM.
- CI (`.github/workflows/ci.yml`) has no unit tests; it builds every package
  attr (excluding `default` and `update`) one at a time for `x86_64-linux` and
  pushes results to Cachix on `main`.

### Non-obvious gotchas

- **`ladybird` and `skia` are multi-hour source compiles** (CI allows 360 min).
  Do not build them casually — prefer the Cachix cache, and only build locally
  when actually working on them.
- **GUI apps** (`pulp`, `mimic`, `portfolio`, `halloy`, `zed-preview`) are
  Linux GTK/Qt desktop apps and need a display to actually run; they still
  `nix build` headlessly.
- `pullrun` currently fails its `versionCheckPhase` (the prebuilt binary reports
  an older version than the packaged `version`). This is a pre-existing
  upstream/packaging mismatch, **not** an environment problem; CI builds each
  package independently so one failure does not block the rest.
- Some CLIs don't accept `--version` (e.g. `boxd` prints usage instead); use
  `--help` to smoke-test those.
