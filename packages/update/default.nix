{
  lib,
  writeShellApplication,
  curl,
  nix,
  python3,
  nodejs,
}:

# Thin wrapper around scripts/update-packages.sh for `nix run .#update`.
# Must run against a writable checkout (not the store copy of this flake).
writeShellApplication {
  name = "update";
  runtimeInputs = [
    curl
    nix
    python3
    # npm for npm-github packages (vit / rook lock regeneration).
    nodejs
  ];
  text = ''
    find_root() {
      local dir="$PWD"
      while true; do
        if [[ -f "$dir/flake.nix" && -x "$dir/scripts/update-packages.sh" ]] \
          || [[ -f "$dir/flake.nix" && -f "$dir/scripts/update-packages.sh" ]]; then
          printf '%s\n' "$dir"
          return 0
        fi
        if [[ "$dir" == "/" ]]; then
          return 1
        fi
        dir="$(dirname "$dir")"
      done
    }

    root="''${AGENTIC_ROOT:-}"
    if [[ -z "$root" ]]; then
      root="$(find_root)" || {
        echo "error: run from the agentic checkout (need flake.nix + scripts/update-packages.sh)" >&2
        echo "  or set AGENTIC_ROOT to the repo path" >&2
        exit 1
      }
    fi

    if [[ ! -f "$root/scripts/update-packages.sh" ]]; then
      echo "error: missing $root/scripts/update-packages.sh" >&2
      exit 1
    fi

    chmod +x "$root/scripts/update-packages.sh" 2>/dev/null || true
    exec bash "$root/scripts/update-packages.sh" "$@"
  '';

  meta = {
    description = "Bump agentic packages/* from their upstream.json sources";
    mainProgram = "update";
  };
}
