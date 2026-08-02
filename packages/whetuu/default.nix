{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
}:

let
  # Prebuilt static (Linux musl) / native (macOS) binaries from GitHub releases.
  # Asset names: whetuu-v{version}-{target}.tar.gz — each archive is a single `whetuu`.
  sources = {
    x86_64-linux = {
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.10/whetuu-v0.1.10-x86_64-linux-musl.tar.gz";
      hash = "sha256-AjffM5kwAqni4UF57hm5krlv1LRjnex1KneNfO8QrUo=";
    };
    aarch64-linux = {
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.10/whetuu-v0.1.10-aarch64-linux-musl.tar.gz";
      hash = "sha256-zZKD0Xn03bpxsQ7W2twKTuolOxxQs8+9ijIVYnfdybA=";
    };
    x86_64-darwin = {
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.10/whetuu-v0.1.10-x86_64-macos.tar.gz";
      hash = "sha256-YKjtOrq7pTNfVQoondgnn1fzhMT4iXCZrAigqYEMvsM=";
    };
    aarch64-darwin = {
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.10/whetuu-v0.1.10-aarch64-macos.tar.gz";
      hash = "sha256-LesgX9KH09nRsu/uvPrQav/t4buXoEEsQY6DZncpH6c=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "whetuu: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "whetuu";
  version = "0.1.10";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # Archive root is just the `whetuu` binary (no directory wrapper).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 whetuu $out/bin/whetuu
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/whetuu";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Opinionated, zero-config cross-shell prompt written in Zig";
    homepage = "https://github.com/yamafaktory/whetuu";
    changelog = "https://github.com/yamafaktory/whetuu/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "whetuu";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
