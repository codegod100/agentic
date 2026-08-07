#!/usr/bin/env bash
# Fast-forward the Radicle mirror from the GitHub upstream (codegod100/agentic).
# Intended for Buildkite scheduled runs and manual dispatch.
#
# Usage:
#   scripts/mirror-from-github.sh
#
# Environment:
#   GITHUB_UPSTREAM_URL   default: https://github.com/codegod100/agentic.git
#   GITHUB_TOKEN          optional; raises GitHub API rate limits for fetch
#   UPSTREAM_BRANCH       default: main
#   RADICLE_BRANCH        branch to update on origin (default: main)
#   RADICLE_GARDEN_EMAIL  push auth (or set RADICLE_PUSH_URL)
#   RADICLE_GARDEN_PASSWORD
#   RADICLE_PUSH_URL      full push URL (overrides email/password)
#   DRY_RUN=1             fetch + compare only; do not merge or push
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM_URL="${GITHUB_UPSTREAM_URL:-https://github.com/codegod100/agentic.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
RADICLE_BRANCH="${RADICLE_BRANCH:-main}"
REMOTE_UPSTREAM="upstream-github"
REMOTE_RADICLE="${RADICLE_REMOTE:-origin}"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need git

upstream_fetch_url() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    # Public repo; token is only for rate limits.
    local path
    path="${UPSTREAM_URL#https://}"
    path="${path#http://}"
    printf 'https://x-access-token:%s@%s' "$GITHUB_TOKEN" "$path"
  else
    printf '%s' "$UPSTREAM_URL"
  fi
}

configure_radicle_push() {
  if [[ -n "${RADICLE_PUSH_URL:-}" ]]; then
    git remote set-url "$REMOTE_RADICLE" "$RADICLE_PUSH_URL"
    return
  fi

  [[ -n "${RADICLE_GARDEN_EMAIL:-}" && -n "${RADICLE_GARDEN_PASSWORD:-}" ]] \
    || die "set RADICLE_PUSH_URL or RADICLE_GARDEN_EMAIL + RADICLE_GARDEN_PASSWORD to push"

  local askpass
  askpass="$(mktemp)"
  trap 'rm -f "$askpass"' EXIT
  cat >"$askpass" <<'EOS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "${GIT_USERNAME:?}" ;;
  *Password*) printf '%s\n' "${GIT_PASSWORD:?}" ;;
  *) exit 1 ;;
esac
EOS
  chmod +x "$askpass"
  export GIT_ASKPASS="$askpass"
  export GIT_TERMINAL_PROMPT=0
  export GIT_USERNAME="$RADICLE_GARDEN_EMAIL"
  export GIT_PASSWORD="$RADICLE_GARDEN_PASSWORD"
}

if ! git remote get-url "$REMOTE_UPSTREAM" >/dev/null 2>&1; then
  git remote add "$REMOTE_UPSTREAM" "$(upstream_fetch_url)"
else
  git remote set-url "$REMOTE_UPSTREAM" "$(upstream_fetch_url)"
fi

log "fetching ${UPSTREAM_URL} (${UPSTREAM_BRANCH})"
git fetch "$REMOTE_UPSTREAM" "$UPSTREAM_BRANCH"

local_sha="$(git rev-parse "$RADICLE_BRANCH")"
upstream_sha="$(git rev-parse "${REMOTE_UPSTREAM}/${UPSTREAM_BRANCH}")"

log "radicle ${RADICLE_BRANCH}: ${local_sha:0:12}"
log "github  ${UPSTREAM_BRANCH}: ${upstream_sha:0:12}"

if [[ "$local_sha" == "$upstream_sha" ]]; then
  log "already up to date"
  exit 0
fi

if ! git merge-base --is-ancestor "$local_sha" "$upstream_sha"; then
  die "histories diverged; refusing non-fast-forward merge (radicle=${local_sha:0:12} github=${upstream_sha:0:12})"
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  log "DRY_RUN: would fast-forward ${RADICLE_BRANCH} to ${upstream_sha:0:12}"
  exit 0
fi

git checkout "$RADICLE_BRANCH"
git merge --ff-only "${REMOTE_UPSTREAM}/${UPSTREAM_BRANCH}"

configure_radicle_push
log "pushing ${RADICLE_BRANCH} to ${REMOTE_RADICLE}"
git push "$REMOTE_RADICLE" "$RADICLE_BRANCH"

log "mirror complete (${upstream_sha:0:12})"
