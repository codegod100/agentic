#!/usr/bin/env bash
# Run update-packages.sh on a Buildkite agent (read-only — no git push or PR).
#
# Default: --check (report outdated packages).
# Set BUILDKITE_FULL_UPDATE=1 to run a full bump + nix build verify (slow; needs npm).
#
# GITHUB_TOKEN is optional; raises GitHub API rate limits when querying upstream.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

source_nix() {
  if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  fi
}

configure_nix() {
  mkdir -p "${HOME}/.config/nix"
  if ! grep -q 'experimental-features' "${HOME}/.config/nix/nix.conf" 2>/dev/null; then
    cat >>"${HOME}/.config/nix/nix.conf" <<'EOF'
experimental-features = nix-command flakes
accept-flake-config = true
EOF
  fi
}

start_nix_daemon() {
  if [[ -S /nix/var/nix/daemon-socket/socket ]]; then
    return 0
  fi
  command -v nix-daemon >/dev/null 2>&1 || die "nix-daemon not found after install"
  log "starting nix-daemon"
  nix-daemon &
  for _ in $(seq 1 30); do
    [[ -S /nix/var/nix/daemon-socket/socket ]] && return 0
    sleep 1
  done
  die "nix-daemon did not become ready"
}

install_nix() {
  command -v nix >/dev/null 2>&1 && return 0
  source_nix
  command -v nix >/dev/null 2>&1 && return 0

  log "installing Nix via Determinate (no systemd on hosted agents)"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install linux \
    --no-confirm --init none --no-start-daemon

  source_nix
  command -v nix >/dev/null 2>&1 || die "nix not available after install"
  start_nix_daemon
  configure_nix
}

install_node() {
  command -v npm >/dev/null 2>&1 && return 0
  log "installing Node.js 22 via nix"
  nix profile install github:NixOS/nixpkgs/nixos-unstable#nodejs_22 --impure
  command -v npm >/dev/null 2>&1 || die "npm not available after node install"
}

install_nix

export GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ "${BUILDKITE_FULL_UPDATE:-0}" == "1" ]]; then
  install_node
  log "running full update (BUILDKITE_FULL_UPDATE=1)"
  exec ./scripts/update-packages.sh "$@"
fi

log "running upstream check (--check)"
set +e
./scripts/update-packages.sh --check
code=$?
set -e
if [ "$code" -eq 0 ]; then
  log "all packages up to date"
  exit 0
fi
if [ "$code" -eq 1 ]; then
  log "outdated packages reported (exit 1) — Buildkite tooling OK"
  exit 0
fi
exit "$code"
