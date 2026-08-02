{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage (finalAttrs: {
  pname = "vit";
  version = "0.6.2";

  src = fetchFromGitHub {
    owner = "solpbc";
    repo = "vit";
    rev = "v${finalAttrs.version}";
    hash = "sha256-n9mniNcWly8XPhjLgsGlwJtjCYlYatNFvBuN7pz+7hg=";
  };

  # Upstream's package-lock.json (often produced via bun) is missing "resolved"
  # URLs, which breaks nixpkgs' offline npm cache. This lockfile was regenerated
  # with `npm install --package-lock-only` against the same version.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # Prefetched offline npm dependency cache.
  # To update after a version bump:
  #   1. Bump version/rev/src hash
  #   2. Regenerate packages/vit/package-lock.json (see README)
  #   3. Set npmDepsHash = lib.fakeHash, build once, paste the hash nix prints
  npmDepsHash = "sha256-8PojaMjFF8mPYmFA9cM3qdaphyCMHoRvMLX/leFOf4A=";

  # Pure JS CLI — no compile step. Upstream Makefile runs `bun install` (dev only).
  dontNpmBuild = true;
  dontBuild = true;

  # Upstream postinstall copies agent skills into $HOME; skip in the build sandbox.
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Social toolkit for personalized software (AT Protocol capability CLI)";
    homepage = "https://v-it.org";
    changelog = "https://github.com/solpbc/vit/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "vit";
    platforms = lib.platforms.all;
  };
})
