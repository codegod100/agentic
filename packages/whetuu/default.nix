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
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.5/whetuu-v0.1.5-x86_64-linux-musl.tar.gz";
      hash = "sha256-YJ8IdY7fe1e9/H1TLer/3Dj5pl4cZUdBwR+oPuHW/4Q=";
    };
    aarch64-linux = {
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.5/whetuu-v0.1.5-aarch64-linux-musl.tar.gz";
      hash = "sha256-H3EIRQH8GGuzELr5GAPt0tuvZVSaNn85fohu7Vkbq8o=";
    };
    x86_64-darwin = {
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.5/whetuu-v0.1.5-x86_64-macos.tar.gz";
      hash = "sha256-8mkq3G4s7HFA6gC2pDUZ1aZBA3uAyqoK6zBgZG5nVAk=";
    };
    aarch64-darwin = {
      url = "https://github.com/yamafaktory/whetuu/releases/download/v0.1.5/whetuu-v0.1.5-aarch64-macos.tar.gz";
      hash = "sha256-WTl+7W0zww7aMZTYfBxlSo/rofJy9EYrlhs9KrqlGyo=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "whetuu: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "whetuu";
  version = "0.1.5";

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
