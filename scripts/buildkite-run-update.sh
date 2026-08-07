#!/usr/bin/env bash
# Run update-packages.sh on a Buildkite agent (read-only — no git push or PR).
#
# GITHUB_TOKEN is optional; raises GitHub API rate limits when bumping packages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

source_nix() {
  if [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  elif [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
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

install_nix() {
  command -v nix >/dev/null 2>&1 && return 0
  source_nix
  command -v nix >/dev/null 2>&1 && return 0

  log "installing Nix (single-user; hosted agents have no systemd)"
  # Determinate installer fails when systemd is inactive; use official no-daemon install.
  curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon --yes
  source_nix
  command -v nix >/dev/null 2>&1 || die "nix not available after install"
  configure_nix
}

install_node() {
  command -v npm >/dev/null 2>&1 && return 0
  log "installing Node.js 22 via nix-env"
  nix-env -iA nixpkgs.nodejs_22 -f https://nixos.org/channels/nixpkgs-unstable
  command -v npm >/dev/null 2>&1 || die "npm not available after node install"
}

install_nix
install_node

log "running update-packages.sh"
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"
exec ./scripts/update-packages.sh "$@"
