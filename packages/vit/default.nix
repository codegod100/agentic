{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage (finalAttrs: {
  pname = "vit";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "solpbc";
    repo = "vit";
    rev = "v${finalAttrs.version}";
    hash = "sha256-iICVLod9SnBxm/4nQuD/cecOobP7QHRgG4LZmZEUYRg=";
  };

  # Prefetched offline npm dependency cache (from package-lock.json).
  # To update after a version bump: set to lib.fakeHash, build once, paste the hash nix prints.
  npmDepsHash = "sha256-nH6gXa7r8n3yxF96B8Ep6kATFrPbANg43V3EatqiITQ=";

  # Pure JS CLI — package.json has no "build" script.
  dontNpmBuild = true;

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
