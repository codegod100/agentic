#!/usr/bin/env bash
# Update packages/* from their upstream sources.
# Intended for local use and weekly CI (see .github/workflows/update-packages.yml).
#
# Usage:
#   scripts/update-packages.sh            # update all packages that have upstream.json
#   scripts/update-packages.sh vit        # update only vit
#   scripts/update-packages.sh --check    # report outdated packages; exit 1 if any
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
CHECK_ONLY=0
PACKAGES=()

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    -*)
      die "unknown flag: $arg"
      ;;
    *)
      PACKAGES+=("$arg")
      ;;
  esac
done

need curl
need nix
need nix-prefetch-url
need python3

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  while IFS= read -r d; do
    name="$(basename "$d")"
    [[ -f "$d/upstream.json" && -f "$d/default.nix" ]] || continue
    PACKAGES+=("$name")
  done < <(find "$ROOT/packages" -mindepth 1 -maxdepth 1 -type d | sort)
fi

[[ ${#PACKAGES[@]} -gt 0 ]] || die "no packages to update"

read_field() {
  # read_field <file> <json-key>
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"
}

current_version() {
  python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"version\s*=\s*\"([^\"]+)\"", text)
if not m:
    sys.exit("version not found in " + sys.argv[1])
print(m.group(1))
' "$1"
}

set_field_string() {
  # set_field_string <file> <attr> <value>  — replaces first attr = "..."
  local file="$1" attr="$2" value="$3"
  python3 -c '
import re, sys
path, attr, value = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
pat = re.compile(rf"({re.escape(attr)}\s*=\s*\")([^\"]*)(\")", re.M)
new, n = pat.subn(rf"\g<1>{value}\g<3>", text, count=1)
if n != 1:
    sys.exit(f"failed to set {attr} in {path} (matches={n})")
open(path, "w").write(new)
' "$file" "$attr" "$value"
}

set_npm_deps_hash() {
  local file="$1" value="$2"
  python3 -c '
import re, sys
path, value = sys.argv[1], sys.argv[2]
text = open(path).read()
pat = re.compile(r"(npmDepsHash\s*=\s*)([^;]+)(;)")
new, n = pat.subn(rf"\g<1>\"{value}\"\g<3>", text, count=1)
if n != 1:
    sys.exit(f"failed to set npmDepsHash in {path} (matches={n})")
open(path, "w").write(new)
' "$file" "$value"
}

sri_from_url_unpack() {
  local url="$1"
  local base32
  base32="$(nix-prefetch-url --unpack "$url" 2>/dev/null)"
  nix hash convert --hash-algo sha256 --to sri "$base32"
}

latest_github_tag() {
  # latest_github_tag <owner/repo> <prefix>
  local repo="$1" prefix="$2"
  local url="https://api.github.com/repos/${repo}/tags?per_page=30"
  local args=(-fsSL)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" "$url" | python3 -c '
import json, re, sys
prefix = sys.argv[1]
tags = json.load(sys.stdin)
# Prefer semver-ish tags matching prefix
pat = re.compile(r"^" + re.escape(prefix) + r"(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)$")
versions = []
for t in tags:
    name = t.get("name") or ""
    m = pat.match(name)
    if m:
        versions.append((m.group(1), name))
if not versions:
    sys.exit("no matching tags for prefix " + prefix)
# sort by version components
def key(v):
    ver = re.split(r"[+-]", v[0], maxsplit=1)[0]
    return [int(x) for x in ver.split(".")]
versions.sort(key=key)
print(versions[-1][0])
' "$prefix"
}

version_gt() {
  # version_gt a b  => true if a > b (semver-ish, numeric)
  python3 -c '
import re, sys
def parts(v):
    core = re.split(r"[+-]", v, maxsplit=1)[0]
    return [int(x) for x in core.split(".")]
a, b = sys.argv[1], sys.argv[2]
sys.exit(0 if parts(a) > parts(b) else 1)
' "$1" "$2"
}

capture_npm_deps_hash() {
  # Build with fake hash; parse the "got:" line from the FOD mismatch.
  local attr="$1"
  local log
  log="$(mktemp)"
  set +e
  nix build "path:${ROOT}#${attr}" --print-build-logs >"$log" 2>&1
  local status=$?
  set -e
  local got
  got="$(python3 -c '
import re, sys
text = open(sys.argv[1]).read()
# Prefer the last "got:" line (npm-deps FOD).
matches = re.findall(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", text)
if not matches:
    sys.exit(1)
print(matches[-1])
' "$log" 2>/dev/null || true)"
  if [[ -z "$got" ]]; then
    warn "failed to capture npmDepsHash for ${attr}; build log:"
    tail -n 80 "$log" >&2 || true
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  printf '%s\n' "$got"
  return 0
}

verify_build() {
  local attr="$1"
  log "verifying nix build .#${attr}"
  nix build "path:${ROOT}#${attr}" --print-build-logs
}

regenerate_npm_lock() {
  # regenerate_npm_lock <owner/repo> <version> <dest-lock>
  local repo="$1" version="$2" dest="$3"
  need npm
  local tmp archive dir
  tmp="$(mktemp -d)"
  archive="${tmp}/src.tar.gz"
  dir="${tmp}/src"
  curl -fsSL "https://github.com/${repo}/archive/refs/tags/v${version}.tar.gz" -o "$archive"
  mkdir -p "$dir"
  tar -xzf "$archive" -C "$dir" --strip-components=1
  (
    cd "$dir"
    rm -f package-lock.json bun.lock
    npm install --package-lock-only --ignore-scripts
  )
  cp "$dir/package-lock.json" "$dest"
  rm -rf "$tmp"
}

update_npm_github() {
  local name="$1"
  local pkg_dir="$ROOT/packages/${name}"
  local default_nix="$pkg_dir/default.nix"
  local upstream="$pkg_dir/upstream.json"
  local repo tag_prefix
  repo="$(read_field "$upstream" github)"
  tag_prefix="$(read_field "$upstream" tag_prefix)"
  [[ -n "$repo" ]] || die "${name}: upstream.json missing github"
  tag_prefix="${tag_prefix:-v}"

  local cur latest
  cur="$(current_version "$default_nix")"
  log "${name}: current=${cur}"
  latest="$(latest_github_tag "$repo" "$tag_prefix")"
  log "${name}: latest upstream=${latest}"

  if ! version_gt "$latest" "$cur"; then
    log "${name}: already up to date"
    return 0
  fi

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    log "${name}: OUTDATED (${cur} -> ${latest})"
    return 10
  fi

  log "${name}: updating ${cur} -> ${latest}"
  set_field_string "$default_nix" version "$latest"

  local src_url src_hash
  src_url="https://github.com/${repo}/archive/refs/tags/${tag_prefix}${latest}.tar.gz"
  log "${name}: prefetching src ${src_url}"
  src_hash="$(sri_from_url_unpack "$src_url")"
  # The hash = "..." inside fetchFromGitHub — set the first hash = "..." after fetchFromGitHub
  python3 -c '
import re, sys
path, value = sys.argv[1], sys.argv[2]
text = open(path).read()
# Replace hash inside fetchFromGitHub block only (first hash = "sha256-...")
pat = re.compile(r"(fetchFromGitHub\s*\{[^}]*?hash\s*=\s*\")([^\"]+)(\")", re.S)
new, n = pat.subn(rf"\g<1>{value}\g<3>", text, count=1)
if n != 1:
    sys.exit(f"failed to set src hash (matches={n})")
open(path, "w").write(new)
' "$default_nix" "$src_hash"
  log "${name}: src hash ${src_hash}"

  if [[ -f "$pkg_dir/package-lock.json" ]]; then
    log "${name}: regenerating package-lock.json"
    regenerate_npm_lock "$repo" "$latest" "$pkg_dir/package-lock.json"
  fi

  log "${name}: computing npmDepsHash"
  set_npm_deps_hash "$default_nix" "$FAKE_HASH"
  local npm_hash
  npm_hash="$(capture_npm_deps_hash "$name")"
  set_npm_deps_hash "$default_nix" "$npm_hash"
  log "${name}: npmDepsHash ${npm_hash}"

  verify_build "$name"
  log "${name}: updated successfully to ${latest}"
}

UPDATED=0
OUTDATED=0

for name in "${PACKAGES[@]}"; do
  pkg_dir="$ROOT/packages/${name}"
  [[ -d "$pkg_dir" ]] || die "unknown package: ${name}"
  [[ -f "$pkg_dir/upstream.json" ]] || die "${name}: missing packages/${name}/upstream.json"
  [[ -f "$pkg_dir/default.nix" ]] || die "${name}: missing packages/${name}/default.nix"

  type="$(read_field "$pkg_dir/upstream.json" type)"
  case "$type" in
    npm-github)
      status=0
      update_npm_github "$name" || status=$?
      if [[ $status -eq 10 ]]; then
        OUTDATED=$((OUTDATED + 1))
      elif [[ $status -ne 0 ]]; then
        exit "$status"
      else
        # detect if files changed for this package
        if [[ "$CHECK_ONLY" -eq 0 ]] && ! git -C "$ROOT" diff --quiet -- "packages/${name}" 2>/dev/null; then
          UPDATED=$((UPDATED + 1))
        fi
      fi
      ;;
    *)
      die "${name}: unsupported upstream type '${type}'"
      ;;
  esac
done

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  if [[ "$OUTDATED" -gt 0 ]]; then
    log "${OUTDATED} package(s) outdated"
    exit 1
  fi
  log "all packages up to date"
  exit 0
fi

log "done (${UPDATED} package dir(s) with local changes)"
