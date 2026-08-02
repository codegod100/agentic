#!/usr/bin/env bash
# Compile packages.ladybird inside `nix develop .#ladybird` (stdenv genericBuild).
#
# Usage (from repo root):
#   ./scripts/ladybird-devshell-build.sh
#   OUT_DIR=/tmp/ladybird-out ./scripts/ladybird-devshell-build.sh
#
# Prefer `nix build .#ladybird` when you only need the package. This script is
# for verifying the develop-shell toolchain and writable $out flow.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Host toolchains (e.g. rustup under /usr/local/cargo) must not shadow Nix's.
scrub_path() {
  echo "$1" | tr ':' '\n' | grep -v '/usr/local/cargo' | grep -v '/.cargo/' | paste -sd: -
}

export PATH
PATH="$(scrub_path "$PATH")"
# Drop host cargo home so cargoSetupHook / rustc use the Nix toolchain.
unset CARGO_HOME || true
unset RUSTUP_HOME || true

out_dir="${OUT_DIR:-$root/outputs/out}"
build_dir="${BUILD_DIR:-$root/outputs/build}"
mkdir -p "$out_dir" "$build_dir"

echo "ladybird develop-shell build → $out_dir (workdir $build_dir)" >&2

# Note: do not enable `set -u` inside the develop shell. nixpkgs'
# cargoSetupHook does `if [ -z $cargoVendorDir ]` (unquoted, no default),
# which aborts under nounset when cargoVendorDir is unset (the normal case
# when using cargoDeps = fetchCargoVendor { ... }).
#
# Run genericBuild in a dedicated workdir so unpackPhase does not leave a
# `source/` tree in the repo root (and so retries are clean).
nix develop .#ladybird -c bash --norc --noprofile -lc "
  set -eo pipefail
  export PATH=\"\$(echo \"\$PATH\" | tr ':' '\\n' | grep -v /usr/local/cargo | grep -v /.cargo/ | paste -sd: -)\"
  unset CARGO_HOME RUSTUP_HOME
  : \"\${src:?missing src}\" \"\${cmakeFlags:?missing cmakeFlags}\"
  source \"\$stdenv/setup\"
  # stdenv sets NIX_ENFORCE_PURITY=1, which makes the gcc-wrapper ignore -I paths
  # outside the Nix store. genericBuild unpacks into a workspace workdir, so
  # Ladybird's -I\$srcdir/AK... includes would otherwise fail as 'No such file'.
  export NIX_ENFORCE_PURITY=0
  export out=$(printf '%q' "$out_dir")
  work=$(printf '%q' "$build_dir")
  rm -rf \"\$work\"
  mkdir -p \"\$out\" \"\$work\"
  cd \"\$work\"
  echo \"NIX_BUILD_CORES=\${NIX_BUILD_CORES:-} NIX_ENFORCE_PURITY=\$NIX_ENFORCE_PURITY rustc=\$(command -v rustc) cwd=\$PWD\" >&2
  genericBuild
  echo \"installed:\" >&2
  ls -la \"\$out/bin\" >&2 || ls -la \"\$out\" >&2
"
