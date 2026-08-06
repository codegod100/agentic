{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  python3,
  cmake,
  pkg-config,
  cacert,
}:

buildNpmPackage.override { nodejs = nodejs_22; } (finalAttrs: {
  pname = "prime-agent";
  version = "0.7.0";

  # Official prebuilt npm pack from GitHub Releases (includes dist/).
  # Sibling workspace packages are pulled in as upstream R2 CDN URL deps.
  src = fetchurl {
    url = "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${finalAttrs.version}/prime-agent-${finalAttrs.version}.tgz";
    hash = "sha256-iLZXhRjHLNUaglvIDyjg/vmmTGfeSn1v16/Xyhs02gs=";
  };

  # npm pack layout
  sourceRoot = "package";

  # Vendored lock with resolved URLs (release tarball ships none).
  # Sibling @earendil-works/* packages resolve via upstream's R2 CDN URLs
  # (same bytes as the GitHub release assets).
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-hs/Fe8GrR1DOncpN0C0Z5ruDC8kDYICMH/dCAV84ylA=";

  # npm needs a writable cache when installing URL/GitHub tarball deps.
  makeCacheWritable = true;

  # Prebuilt JS; only need to install/link deps (incl. zeromq native addon).
  dontNpmBuild = true;
  dontBuild = true;

  # cmake/pkg-config are only on PATH for zeromq's cmake-ts install script;
  # do not run a top-level CMake configure against the npm pack.
  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    python3
    cmake
    pkg-config
  ];

  # zeromq's cmake-ts install fetches/builds native code and needs CA certs.
  env = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NODE_OPTIONS = "--use-openssl-ca";
  };

  meta = {
    description = "Self-improving RLM agent for coding workflows and long-running autonomous tasks";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "prime-agent";
    platforms = lib.platforms.unix;
  };
})
