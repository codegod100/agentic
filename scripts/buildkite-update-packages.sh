#!/usr/bin/env bash
# Run weekly package bumps and open a GitHub PR (Buildkite scheduled builds).
#
# Usage:
#   GITHUB_TOKEN=ghp_… ./scripts/buildkite-update-packages.sh
#   GITHUB_TOKEN=ghp_… ./scripts/buildkite-update-packages.sh vit rook
#
# Environment:
#   GITHUB_TOKEN        required — repo contents + pull-requests write
#   GITHUB_REPOSITORY   default: codegod100/agentic
#   UPDATE_BRANCH       default: chore/update-packages
#   DRY_RUN=1           run updates but do not commit or open a PR
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="${GITHUB_REPOSITORY:-codegod100/agentic}"
BRANCH="${UPDATE_BRANCH:-chore/update-packages}"
BASE="${UPDATE_BASE:-main}"

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN is required"

install_nix() {
  command -v nix >/dev/null 2>&1 && return 0
  log "installing Nix"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install linux --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null \
    || . "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null \
    || true
  command -v nix >/dev/null 2>&1 || die "nix not available after install"
}

install_node() {
  command -v npm >/dev/null 2>&1 && return 0
  if command -v nix >/dev/null 2>&1; then
    log "installing Node.js 22 via nix"
    nix profile install "github:NixOS/nixpkgs/nixos-unstable#nodejs_22" --impure 2>/dev/null \
      || nix-env -iA nixpkgs.nodejs_22 2>/dev/null \
      || true
  fi
  command -v npm >/dev/null 2>&1 || die "npm is required (install Node.js 22)"
}

install_nix
install_node

log "updating packages"
export GITHUB_TOKEN
chmod +x scripts/update-packages.sh
if [[ $# -gt 0 ]]; then
  ./scripts/update-packages.sh "$@"
else
  ./scripts/update-packages.sh
fi

if git diff --quiet -- packages/; then
  log "no package changes; done"
  exit 0
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  log "DRY_RUN: would open PR for package changes"
  git diff --stat -- packages/
  exit 0
fi

git config user.name "${GIT_AUTHOR_NAME:-buildkite}"
git config user.email "${GIT_AUTHOR_EMAIL:-buildkite@users.noreply.github.com}"

log "committing package bumps on ${BRANCH}"
git checkout -B "$BRANCH"
git add packages/
git commit -m "$(cat <<EOF
chore(packages): weekly upstream version bumps

Automated update from Buildkite scripts/buildkite-update-packages.sh
EOF
)"

REMOTE="https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git"
git push -f "$REMOTE" "HEAD:${BRANCH}"

log "opening pull request"
PR_PAYLOAD="$(python3 -c '
import json, os, sys
repo = os.environ["REPO"]
branch = os.environ["BRANCH"]
base = os.environ["BASE"]
print(json.dumps({
    "title": "chore(packages): weekly upstream version bumps",
    "head": branch,
    "base": base,
    "body": (
        "## Weekly package update\n\n"
        "Opened by Buildkite (`scripts/buildkite-update-packages.sh`).\n\n"
        "Re-checks each `packages/*/upstream.json`, refreshes hashes/lockfiles, "
        "and verifies `nix build` for bumped packages."
    ),
}))
' REPO="$REPO" BRANCH="$BRANCH" BASE="$BASE")"

EXISTING_PR="$(curl -fsS \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/pulls?head=${REPO%%/*}:${BRANCH}&state=open" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["number"] if d else "")')"

if [[ -n "$EXISTING_PR" ]]; then
  log "updated existing PR #${EXISTING_PR}"
  curl -fsS -X PATCH \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/pulls/${EXISTING_PR}" \
    -d '{"body":"Branch force-pushed by latest Buildkite weekly update."}' >/dev/null
else
  PR_NUM="$(curl -fsS -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/pulls" \
    -d "$PR_PAYLOAD" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("number",""))')"
  [[ -n "$PR_NUM" ]] || die "failed to create pull request"
  log "created PR #${PR_NUM}: https://github.com/${REPO}/pull/${PR_NUM}"
fi
