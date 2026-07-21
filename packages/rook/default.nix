{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage (finalAttrs: {
  pname = "rook";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "solpbc";
    repo = "rook";
    rev = "v${finalAttrs.version}";
    hash = "sha256-UCoGUWn37062HzcE1czgSoenINX9kIKpz0c4xUaYptY=";
  };

  # Vendored so automated updates can regenerate a lock with resolved URLs
  # if upstream's lock ever drifts (same pattern as vit).
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # Prefetched offline npm dependency cache.
  # To update after a version bump:
  #   1. Bump version/rev/src hash
  #   2. Regenerate packages/rook/package-lock.json (see README)
  #   3. Set npmDepsHash = lib.fakeHash, build once, paste the hash nix prints
  npmDepsHash = "sha256-GGsQNNTyXSyfUDkYCD6bctDIV+IbAeV4d415upoLgx8=";

  # Pure JS CLI — no compile step.
  dontNpmBuild = true;
  dontBuild = true;

  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Agent-native identity and authentication CLI for rook.host";
    homepage = "https://rook.host";
    changelog = "https://github.com/solpbc/rook/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "rook";
    platforms = lib.platforms.all;
  };
})
