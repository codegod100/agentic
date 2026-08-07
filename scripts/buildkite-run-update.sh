#!/usr/bin/env bash
# Weekly Buildkite package check → Radicle patch when outdated.
#
# 1. Run update-packages.sh --check against this checkout (GitHub clone).
# 2. If up to date → exit 0.
# 3. If outdated → install rad, clone the Radicle RID, bump packages there,
#    commit, and open (or update) a Radicle patch via `git push rad …:refs/patches`.
#
# Env (optional unless noted):
#   GITHUB_TOKEN              Higher GitHub API rate limits
#   RADICLE_RID               Default rad:z6BdNEojb6XZcor7SMkYpXn45Zp8
#   RADICLE_SEED              NID@host:port for nandi.radicle.garden
#   RADICLE_HTTP_API          Default https://nandi.radicle.garden/api/v1
#   RAD_PASSPHRASE            Passphrase for radicle keys (recommended)
#   RADICLE_ALIAS             Alias for rad auth (default: buildkite-agent)
#   RADICLE_SECRET_KEY        OpenSSH private key body (or path) for persistent DID
#   RADICLE_PUBLIC_KEY        Matching .pub line (or path)
#   BUILDKITE_FULL_UPDATE=1    Skip --check; always bump + patch if dirty
#   SKIP_RADICLE_PATCH=1      Bump only; do not open a Radicle patch
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RADICLE_RID="${RADICLE_RID:-rad:z6BdNEojb6XZcor7SMkYpXn45Zp8}"
RADICLE_SEED="${RADICLE_SEED:-z6MknYm3iSpuY5hLCH93K5Ls5KG7cBK4fQwybqcHzxDsT2jU@nandi.radicle.garden:58019}"
RADICLE_SEED_NID="${RADICLE_SEED%%@*}"
RADICLE_HTTP_API="${RADICLE_HTTP_API:-https://nandi.radicle.garden/api/v1}"
RADICLE_ALIAS="${RADICLE_ALIAS:-buildkite-agent}"
PATCH_TITLE="${RADICLE_PATCH_TITLE:-chore(packages): weekly upstream version bumps}"
export PATH="${HOME}/.radicle/bin:${PATH}"
export RAD_HOME="${RAD_HOME:-${HOME}/.radicle}"

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

install_rad() {
  if command -v rad >/dev/null 2>&1 && command -v git-remote-rad >/dev/null 2>&1; then
    return 0
  fi
  log "installing Radicle CLI"
  curl -sSLf https://radicle.dev/install | sh -s -- --no-modify-path
  export PATH="${HOME}/.radicle/bin:${PATH}"
  command -v rad >/dev/null 2>&1 || die "rad not available after install"
  command -v git-remote-rad >/dev/null 2>&1 || die "git-remote-rad not available after install"
}

write_key_material() {
  local dest="$1" value="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$value" ]]; then
    cp "$value" "$dest"
  else
    printf '%s\n' "$value" >"$dest"
  fi
  chmod 600 "$dest" 2>/dev/null || true
}

ensure_rad_identity() {
  if [[ -f "${RAD_HOME}/keys/radicle" && -f "${RAD_HOME}/keys/radicle.pub" ]]; then
    log "using existing Radicle identity at ${RAD_HOME}"
    return 0
  fi

  if [[ -n "${RADICLE_SECRET_KEY:-}" && -n "${RADICLE_PUBLIC_KEY:-}" ]]; then
    log "installing Radicle keys from environment"
    write_key_material "${RAD_HOME}/keys/radicle" "${RADICLE_SECRET_KEY}"
    write_key_material "${RAD_HOME}/keys/radicle.pub" "${RADICLE_PUBLIC_KEY}"
    chmod 600 "${RAD_HOME}/keys/radicle"
    chmod 644 "${RAD_HOME}/keys/radicle.pub"
    [[ -f "${RAD_HOME}/config.json" ]] || rad config init >/dev/null
    return 0
  fi

  [[ -n "${RAD_PASSPHRASE:-}" ]] || export RAD_PASSPHRASE="buildkite-ephemeral"
  log "creating Radicle identity alias=${RADICLE_ALIAS}"
  printf '%s\n' "${RAD_PASSPHRASE}" | rad auth --stdin --alias "${RADICLE_ALIAS}"
}

configure_rad_seed() {
  python3 -c '
import json, os, sys
path = os.path.join(os.environ["RAD_HOME"], "config.json")
seed = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)
prefs = cfg.get("preferredSeeds") or []
connect = (cfg.get("node") or {}).get("connect") or []
if seed not in prefs:
    prefs = [seed] + [s for s in prefs if s != seed]
    cfg["preferredSeeds"] = prefs
cfg.setdefault("node", {})
if seed not in connect:
    connect = [seed] + [s for s in connect if s != seed]
    cfg["node"]["connect"] = connect
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
' "${RADICLE_SEED}"
}

ensure_rad_node() {
  if rad node status >/dev/null 2>&1; then
    log "Radicle node already running"
  else
    log "starting Radicle node"
    rad node start
  fi
  configure_rad_seed
  # Reconnect after preferredSeeds / connect updates.
  rad node stop >/dev/null 2>&1 || true
  rad node start
  for _ in $(seq 1 30); do
    if rad node status 2>/dev/null | grep -q "${RADICLE_SEED_NID}"; then
      return 0
    fi
    sleep 1
  done
  log "warning: garden seed ${RADICLE_SEED_NID} not yet listed in node status (continuing)"
}

rad_workdir() {
  printf '%s' "${RADICLE_WORKDIR:-${TMPDIR:-/tmp}/agentic-radicle-patch}"
}

clone_rad_workdir() {
  local dir
  dir="$(rad_workdir)"
  rm -rf "$dir"
  log "cloning ${RADICLE_RID} from seed ${RADICLE_SEED_NID} → ${dir}"
  rad clone "${RADICLE_RID}" --seed "${RADICLE_SEED_NID}" --timeout 60s "$dir"
  git -C "$dir" config user.email "${GIT_AUTHOR_EMAIL:-buildkite@agentic.local}"
  git -C "$dir" config user.name "${GIT_AUTHOR_NAME:-Buildkite}"
  git -C "$dir" config commit.gpgsign false
  printf '%s\n' "$dir"
}

find_open_package_patch() {
  # Prints patch id of an open patch with our weekly title, if any.
  python3 -c '
import json, sys, urllib.request
api, rid, title = sys.argv[1], sys.argv[2], sys.argv[3]
url = api.rstrip("/") + "/repos/" + rid + "/patches"
with urllib.request.urlopen(url, timeout=30) as r:
    patches = json.load(r)
for p in patches:
    state = (p.get("state") or {}).get("status") or ""
    if state != "open":
        continue
    if (p.get("title") or "") == title:
        print(p["id"])
        sys.exit(0)
' "${RADICLE_HTTP_API}" "${RADICLE_RID}" "${PATCH_TITLE}" 2>/dev/null || true
}

open_or_update_patch() {
  local dir="$1"
  local existing
  existing="$(find_open_package_patch || true)"
  cd "$dir"
  git checkout -B chore/update-packages >/dev/null 2>&1 || git checkout -B chore/update-packages

  if [[ -n "$existing" ]]; then
    log "updating existing Radicle patch ${existing}"
    git push --force-with-lease \
      -c "push.pushOption=patch.message=${PATCH_TITLE}" \
      rad "HEAD:patches/${existing}"
  else
    log "opening new Radicle patch"
    # Title falls back to the commit subject if the push option is ignored.
    git push \
      -c "push.pushOption=patch.message=${PATCH_TITLE}" \
      rad HEAD:refs/patches
  fi
}

run_full_update_and_patch() {
  install_node
  install_rad
  ensure_rad_identity
  ensure_rad_node

  local dir
  dir="$(clone_rad_workdir)"

  log "running full package update in Radicle worktree"
  # Prefer this checkout's updater (GitHub tip) against the Radicle tree.
  AGENTIC_ROOT="$dir" "$ROOT/scripts/update-packages.sh"

  if git -C "$dir" diff --quiet -- packages; then
    log "no package file changes after update — nothing to patch"
    return 0
  fi

  if [[ "${SKIP_RADICLE_PATCH:-0}" == "1" ]]; then
    log "SKIP_RADICLE_PATCH=1 — leaving local changes in ${dir}"
    return 0
  fi

  git -C "$dir" add packages
  git -C "$dir" commit -m "${PATCH_TITLE}"
  open_or_update_patch "$dir"
  log "Radicle patch published for ${RADICLE_RID}"
}

install_nix
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ "${BUILDKITE_FULL_UPDATE:-0}" == "1" ]]; then
  log "BUILDKITE_FULL_UPDATE=1 — bump + Radicle patch"
  run_full_update_and_patch
  exit 0
fi

log "running upstream check (--check)"
set +e
./scripts/update-packages.sh --check
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  log "all packages up to date"
  exit 0
fi

if [[ "$code" -eq 1 ]]; then
  log "outdated packages detected — bumping and opening Radicle patch"
  run_full_update_and_patch
  exit 0
fi

exit "$code"
