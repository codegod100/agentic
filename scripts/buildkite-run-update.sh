#!/usr/bin/env bash
# Run update-packages.sh on a Buildkite agent (read-only — no git push or PR).
#
# GITHUB_TOKEN is optional; raises GitHub API rate limits when bumping packages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() { printf '==> %s\n' "$*"; }

install_nix() {
  command -v nix >/dev/null 2>&1 && return 0
  log "installing Nix"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install linux --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null \
    || . "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null \
    || true
}

install_node() {
  command -v npm >/dev/null 2>&1 && return 0
  if command -v nix >/dev/null 2>&1; then
    log "installing Node.js 22"
    nix profile install "github:NixOS/nixpkgs/nixos-unstable#nodejs_22" --impure 2>/dev/null || true
  fi
}

install_nix
install_node

log "running update-packages.sh"
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"
exec ./scripts/update-packages.sh "$@"
