{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
  versionCheckHook,
}:

let
  # Prebuilt CLI from https://github.com/denoland/celld/releases.
  # Each asset is a gzip-compressed `celld` binary (not a tarball).
  # Platforms match the official release matrix (no darwin-x86_64).
  sources = {
    x86_64-linux = {
      url = "https://github.com/denoland/celld/releases/download/v0.1.0/celld-x86_64-unknown-linux-gnu.gz";
      hash = "sha256-E5NUwoYY/mSIZFmPXN9prpGhdrMrkEGKgT4Cboa+mnw=";
    };
    aarch64-linux = {
      url = "https://github.com/denoland/celld/releases/download/v0.1.0/celld-aarch64-unknown-linux-gnu.gz";
      hash = "sha256-JW0lJ1roU3HAGpp/XcVTvkGu3Zx5tla/a3FURm8AMYI=";
    };
    aarch64-darwin = {
      url = "https://github.com/denoland/celld/releases/download/v0.1.0/celld-aarch64-apple-darwin.gz";
      hash = "sha256-AIZdbb/jPDZDOUCE0Vgx42PcoXtBK0bh+WXFkfT12N4=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "celld: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "celld";
  version = "0.1.0";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  dontUnpack = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libgcc ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    gunzip -c $src > $out/bin/celld
    chmod +x $out/bin/celld
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/celld";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Self-hosted, distributed Durable Objects — run Cloudflare Workers on your own machines";
    homepage = "https://github.com/denoland/celld";
    changelog = "https://github.com/denoland/celld/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "celld";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
