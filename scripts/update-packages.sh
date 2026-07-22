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

set_fetch_from_github_field() {
  # set_fetch_from_github_field <file> <attr> <value>
  # Replaces attr = "..." inside the first fetchFromGitHub { ... } block.
  local file="$1" attr="$2" value="$3"
  python3 -c '
import re, sys
path, attr, value = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
pat = re.compile(
    rf"(fetchFromGitHub\s*\{{[^}}]*?{re.escape(attr)}\s*=\s*\")([^\"]+)(\")",
    re.S,
)
new, n = pat.subn(rf"\g<1>{value}\g<3>", text, count=1)
if n != 1:
    sys.exit(f"failed to set fetchFromGitHub.{attr} in {path} (matches={n})")
open(path, "w").write(new)
' "$file" "$attr" "$value"
}

current_rev() {
  python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"fetchFromGitHub\s*\{[^}]*?rev\s*=\s*\"([^\"]+)\"", text, re.S)
if not m:
    sys.exit("rev not found in " + sys.argv[1])
print(m.group(1))
' "$1"
}

latest_github_commit() {
  # latest_github_commit <owner/repo> <branch>
  # prints: <sha> <YYYY-MM-DD>
  local repo="$1" branch="$2"
  local url="https://api.github.com/repos/${repo}/commits/${branch}"
  local args=(-fsSL)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" "$url" | python3 -c '
import json, sys
c = json.load(sys.stdin)
sha = c["sha"]
date = c["commit"]["committer"]["date"][:10]
print(sha, date)
'
}

sri_from_url_file() {
  local url="$1"
  # nix-prefetch-url (no --unpack) for plain files (gems, etc.)
  local base32
  base32="$(nix-prefetch-url "$url" 2>/dev/null)"
  nix hash convert --hash-algo sha256 --to sri "$base32"
}

refresh_vendored_gems() {
  # refresh_vendored_gems <default.nix> <owner/repo> <rev>
  # If the package vendors prism/rbs gems, re-read versions from upstream
  # Makefile at that rev and refresh fetchurl hashes when they change.
  local default_nix="$1" repo="$2" rev="$3"
  python3 -c '
import re, sys
text = open(sys.argv[1]).read()
sys.exit(0 if re.search(r"prismVersion\s*=", text) else 1)
' "$default_nix" 2>/dev/null || return 0

  local makefile
  makefile="$(mktemp)"
  local args=(-fsSL)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" \
    "https://raw.githubusercontent.com/${repo}/${rev}/Makefile" \
    -o "$makefile"

  local prism_ver rbs_ver
  prism_ver="$(python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"PRISM_VERSION\s*\?=\s*(\S+)", text)
print(m.group(1) if m else "")
' "$makefile")"
  rbs_ver="$(python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"RBS_VERSION\s*\?=\s*(\S+)", text)
print(m.group(1) if m else "")
' "$makefile")"
  rm -f "$makefile"

  [[ -n "$prism_ver" && -n "$rbs_ver" ]] || {
    warn "could not parse PRISM_VERSION/RBS_VERSION from upstream Makefile"
    return 0
  }

  local cur_prism cur_rbs
  cur_prism="$(python3 -c '
import re, sys
m = re.search(r"prismVersion\s*=\s*\"([^\"]+)\"", open(sys.argv[1]).read())
print(m.group(1) if m else "")
' "$default_nix")"
  cur_rbs="$(python3 -c '
import re, sys
m = re.search(r"rbsVersion\s*=\s*\"([^\"]+)\"", open(sys.argv[1]).read())
print(m.group(1) if m else "")
' "$default_nix")"

  if [[ "$prism_ver" != "$cur_prism" ]]; then
    log "  prism ${cur_prism} -> ${prism_ver}"
    set_field_string "$default_nix" prismVersion "$prism_ver"
    local prism_hash
    prism_hash="$(sri_from_url_file "https://rubygems.org/gems/prism-${prism_ver}.gem")"
    python3 -c '
import re, sys
path, ver, h = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
# first fetchurl after prismGem =
pat = re.compile(
    r"(prismGem\s*=\s*fetchurl\s*\{[^}]*?hash\s*=\s*\")([^\"]+)(\")",
    re.S,
)
new, n = pat.subn(rf"\g<1>{h}\g<3>", text, count=1)
if n != 1:
    sys.exit(f"failed to set prismGem hash (matches={n})")
open(path, "w").write(new)
' "$default_nix" "$prism_ver" "$prism_hash"
    log "  prism gem hash ${prism_hash}"
  fi

  if [[ "$rbs_ver" != "$cur_rbs" ]]; then
    log "  rbs ${cur_rbs} -> ${rbs_ver}"
    set_field_string "$default_nix" rbsVersion "$rbs_ver"
    local rbs_hash
    rbs_hash="$(sri_from_url_file "https://rubygems.org/gems/rbs-${rbs_ver}.gem")"
    python3 -c '
import re, sys
path, h = sys.argv[1], sys.argv[2]
text = open(path).read()
pat = re.compile(
    r"(rbsGem\s*=\s*fetchurl\s*\{[^}]*?hash\s*=\s*\")([^\"]+)(\")",
    re.S,
)
new, n = pat.subn(rf"\g<1>{h}\g<3>", text, count=1)
if n != 1:
    sys.exit(f"failed to set rbsGem hash (matches={n})")
open(path, "w").write(new)
' "$default_nix" "$rbs_hash"
    log "  rbs gem hash ${rbs_hash}"
  fi
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
  set_fetch_from_github_field "$default_nix" hash "$src_hash"
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

latest_github_tag_with_suffix() {
  # latest_github_tag_with_suffix <owner/repo> <prefix> <suffix>
  # e.g. prefix=v suffix=-pre  => matches v1.12.0-pre, prints 1.12.0-pre
  local repo="$1" prefix="$2" suffix="$3"
  local url="https://api.github.com/repos/${repo}/releases?per_page=30"
  local args=(-fsSL)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" "$url" | python3 -c '
import json, re, sys
prefix, suffix = sys.argv[1], sys.argv[2]
releases = json.load(sys.stdin)
pat = re.compile(
    r"^" + re.escape(prefix) + r"(\d+\.\d+\.\d+)" + re.escape(suffix) + r"$"
)
versions = []
for r in releases:
    if r.get("draft"):
        continue
    name = r.get("tag_name") or ""
    m = pat.match(name)
    if m:
        versions.append(m.group(1) + suffix)
if not versions:
    sys.exit("no matching release tags for prefix=%r suffix=%r" % (prefix, suffix))
def key(v):
    core = re.split(r"[+-]", v, maxsplit=1)[0]
    return [int(x) for x in core.split(".")]
versions.sort(key=key)
print(versions[-1])
' "$prefix" "$suffix"
}

set_fetchurl_hash() {
  # set_fetchurl_hash <file> <value>
  # Replaces hash = "..." inside the first fetchurl { ... } block.
  local file="$1" value="$2"
  python3 -c '
import re, sys
path, value = sys.argv[1], sys.argv[2]
text = open(path).read()
pat = re.compile(
    r"(fetchurl\s*\{[^}]*?hash\s*=\s*\")([^\"]+)(\")",
    re.S,
)
new, n = pat.subn(rf"\g<1>{value}\g<3>", text, count=1)
if n != 1:
    sys.exit(f"failed to set fetchurl.hash in {path} (matches={n})")
open(path, "w").write(new)
' "$file" "$value"
}

update_github_release_binary() {
  # Official prebuilt release assets (e.g. zed-preview Linux tarball).
  # version in default.nix is the tag without the leading "v" (e.g. 1.12.0-pre).
  local name="$1"
  local pkg_dir="$ROOT/packages/${name}"
  local default_nix="$pkg_dir/default.nix"
  local upstream="$pkg_dir/upstream.json"
  local repo tag_prefix tag_suffix asset
  repo="$(read_field "$upstream" github)"
  tag_prefix="$(read_field "$upstream" tag_prefix)"
  tag_suffix="$(read_field "$upstream" tag_suffix)"
  asset="$(read_field "$upstream" asset)"
  [[ -n "$repo" ]] || die "${name}: upstream.json missing github"
  [[ -n "$asset" ]] || die "${name}: upstream.json missing asset"
  tag_prefix="${tag_prefix:-v}"
  tag_suffix="${tag_suffix:-}"

  local cur latest
  cur="$(current_version "$default_nix")"
  log "${name}: current=${cur}"
  latest="$(latest_github_tag_with_suffix "$repo" "$tag_prefix" "$tag_suffix")"
  log "${name}: latest upstream=${latest}"

  if [[ "$latest" == "$cur" ]]; then
    log "${name}: already up to date"
    return 0
  fi

  # Semver compare on the numeric core (ignore -pre etc.)
  local cur_core latest_core
  cur_core="${cur%%-*}"; cur_core="${cur_core%%+*}"
  latest_core="${latest%%-*}"; latest_core="${latest_core%%+*}"
  if ! version_gt "$latest_core" "$cur_core" && [[ "$latest" != "$cur" ]]; then
    # Same core version but different suffix, or non-monotonic tag: still update
    # when the full tag string differs (handled above). If latest core is older,
    # skip to avoid downgrades.
    if ! version_gt "$latest_core" "$cur_core" && [[ "$latest_core" != "$cur_core" ]]; then
      log "${name}: latest core ${latest_core} is not newer than ${cur_core}; skipping"
      return 0
    fi
  fi

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    log "${name}: OUTDATED (${cur} -> ${latest})"
    return 10
  fi

  log "${name}: updating ${cur} -> ${latest}"
  set_field_string "$default_nix" version "$latest"

  local src_url src_hash
  src_url="https://github.com/${repo}/releases/download/${tag_prefix}${latest}/${asset}"
  log "${name}: prefetching ${src_url}"
  src_hash="$(sri_from_url_file "$src_url")"
  set_fetchurl_hash "$default_nix" "$src_hash"
  log "${name}: src hash ${src_hash}"

  verify_build "$name"
  log "${name}: updated successfully to ${latest}"
}

update_url_manifest_binary() {
  # Prebuilt multi-platform binaries discovered via a version manifest URL.
  # upstream.json:
  #   type: url-manifest-binary
  #   manifest_url: "https://…/latest-{platform}.json"  ({platform} substituted)
  #   platforms: { "x86_64-linux": "linux-amd64", … }
  #
  # default.nix is expected to declare:
  #   version = "…";
  #   sources = { <nix-system> = { url = "…"; hash = "…"; }; … };
  local name="$1"
  local pkg_dir="$ROOT/packages/${name}"
  local default_nix="$pkg_dir/default.nix"
  local upstream="$pkg_dir/upstream.json"
  local manifest_url
  manifest_url="$(read_field "$upstream" manifest_url)"
  [[ -n "$manifest_url" ]] || die "${name}: upstream.json missing manifest_url"

  local cur latest
  cur="$(current_version "$default_nix")"
  log "${name}: current=${cur}"

  # Fetch all platform manifests; require a single shared version.
  local platform_data
  platform_data="$(python3 -c '
import json, os, re, subprocess, sys, urllib.request

upstream = json.load(open(sys.argv[1]))
manifest_tmpl = upstream["manifest_url"]
platforms = upstream["platforms"]
if not platforms:
    sys.exit("platforms map is empty")

entries = {}
versions = set()
for nix_system, platform in platforms.items():
    url = manifest_tmpl.replace("{platform}", platform)
    with urllib.request.urlopen(url) as r:
        m = json.load(r)
    ver = m.get("version") or ""
    bin_url = m.get("url") or ""
    if not ver or not bin_url:
        sys.exit(f"invalid manifest for {platform}: {m!r}")
    versions.add(ver)
    entries[nix_system] = {"url": bin_url, "platform": platform}
if len(versions) != 1:
    sys.exit(f"platform versions disagree: {sorted(versions)}")
version = versions.pop()
print(json.dumps({"version": version, "entries": entries}))
' "$upstream")"

  latest="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])' <<<"$platform_data")"
  log "${name}: latest upstream=${latest}"

  if [[ "$latest" == "$cur" ]]; then
    # Still refresh hashes if any platform URL/hash drifted without a version bump.
    # Compare by re-prefetching only when check mode is off and we force-check
    # via full equality of the sources block after a dry rewrite.
    if [[ "$CHECK_ONLY" -eq 1 ]]; then
      log "${name}: already up to date"
      return 0
    fi
    # Fall through only if sources need rewriting (handled below with hash refresh).
  fi

  if [[ "$latest" != "$cur" ]]; then
    if [[ "$CHECK_ONLY" -eq 1 ]]; then
      log "${name}: OUTDATED (${cur} -> ${latest})"
      return 10
    fi
    log "${name}: updating ${cur} -> ${latest}"
    set_field_string "$default_nix" version "$latest"
  elif [[ "$CHECK_ONLY" -eq 1 ]]; then
    log "${name}: already up to date"
    return 0
  fi

  # Prefetch each platform binary and rewrite the sources = { … } block.
  local updated_sources
  updated_sources="$(python3 -c '
import json, re, subprocess, sys

platform_data = json.loads(sys.argv[1])
entries = platform_data["entries"]
out = {}
for nix_system, e in entries.items():
    url = e["url"]
    base32 = subprocess.check_output(
        ["nix-prefetch-url", url], text=True
    ).strip().splitlines()[-1]
    sri = subprocess.check_output(
        ["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "sri", base32],
        text=True,
    ).strip()
    out[nix_system] = {"url": url, "hash": sri}
    print(f"  {nix_system}: {sri}", file=sys.stderr)
print(json.dumps(out))
' "$platform_data")"

  python3 -c '
import json, re, sys

path, sources_json = sys.argv[1], sys.argv[2]
sources = json.loads(sources_json)
text = open(path).read()

# Prefer a stable system order.
order = ["x86_64-linux", "aarch64-linux", "x86_64-darwin", "aarch64-darwin"]
keys = [k for k in order if k in sources] + sorted(k for k in sources if k not in order)

def fmt_entry(sysname):
    e = sources[sysname]
    return (
        f"    {sysname} = {{\n"
        f"      url = \"{e['url']}\";\n"
        f"      hash = \"{e['hash']}\";\n"
        f"    }};"
    )

block = "sources = {\n" + "\n".join(fmt_entry(k) for k in keys) + "\n  };"
pat = re.compile(r"sources\s*=\s*\{.*?\n  \};", re.S)
new, n = pat.subn(block, text, count=1)
if n != 1:
    sys.exit(f"failed to rewrite sources block in {path} (matches={n})")
open(path, "w").write(new)
' "$default_nix" "$updated_sources"

  log "${name}: sources refreshed"

  verify_build "$name"
  log "${name}: updated successfully to ${latest}"
}

update_github_unstable() {
  # Track tip of a branch for projects without release tags.
  # version format: 0-unstable-YYYY-MM-DD
  local name="$1"
  local pkg_dir="$ROOT/packages/${name}"
  local default_nix="$pkg_dir/default.nix"
  local upstream="$pkg_dir/upstream.json"
  local repo branch
  repo="$(read_field "$upstream" github)"
  branch="$(read_field "$upstream" branch)"
  [[ -n "$repo" ]] || die "${name}: upstream.json missing github"
  branch="${branch:-master}"

  local cur_rev cur_ver latest_sha latest_date latest_ver
  cur_rev="$(current_rev "$default_nix")"
  cur_ver="$(current_version "$default_nix")"
  log "${name}: current=${cur_ver} (rev ${cur_rev:0:12})"

  read -r latest_sha latest_date < <(latest_github_commit "$repo" "$branch")
  latest_ver="0-unstable-${latest_date}"
  log "${name}: latest ${branch}=${latest_sha:0:12} (${latest_date})"

  if [[ "$latest_sha" == "$cur_rev" ]]; then
    log "${name}: already up to date"
    return 0
  fi

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    log "${name}: OUTDATED (${cur_rev:0:12} -> ${latest_sha:0:12})"
    return 10
  fi

  log "${name}: updating ${cur_rev:0:12} -> ${latest_sha:0:12}"
  set_field_string "$default_nix" version "$latest_ver"
  set_fetch_from_github_field "$default_nix" rev "$latest_sha"

  local src_url src_hash
  src_url="https://github.com/${repo}/archive/${latest_sha}.tar.gz"
  log "${name}: prefetching src ${src_url}"
  src_hash="$(sri_from_url_unpack "$src_url")"
  set_fetch_from_github_field "$default_nix" hash "$src_hash"
  log "${name}: src hash ${src_hash}"

  refresh_vendored_gems "$default_nix" "$repo" "$latest_sha"

  verify_build "$name"
  log "${name}: updated successfully to ${latest_ver} (${latest_sha:0:12})"
}

UPDATED=0
OUTDATED=0

for name in "${PACKAGES[@]}"; do
  pkg_dir="$ROOT/packages/${name}"
  [[ -d "$pkg_dir" ]] || die "unknown package: ${name}"
  [[ -f "$pkg_dir/upstream.json" ]] || die "${name}: missing packages/${name}/upstream.json"
  [[ -f "$pkg_dir/default.nix" ]] || die "${name}: missing packages/${name}/default.nix"

  type="$(read_field "$pkg_dir/upstream.json" type)"
  status=0
  case "$type" in
    npm-github)
      update_npm_github "$name" || status=$?
      ;;
    github-unstable)
      update_github_unstable "$name" || status=$?
      ;;
    github-release-binary)
      update_github_release_binary "$name" || status=$?
      ;;
    url-manifest-binary)
      update_url_manifest_binary "$name" || status=$?
      ;;
    *)
      die "${name}: unsupported upstream type '${type}'"
      ;;
  esac
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
