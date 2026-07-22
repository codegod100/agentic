{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
}:

let
  # Prebuilt static CLI from https://boxd.sh/downloads/cli (see quickstart).
  # Platforms match the installer's PLATFORM matrix (no darwin-x86_64).
  sources = {
    x86_64-linux = {
      url = "https://boxd.sh/downloads/cli/boxd-linux-amd64";
      hash = "sha256-TlUeF41JcsMekeGx4y8dKyjTQ/oyHwJrSxRFLD2nYpc=";
    };
    aarch64-linux = {
      url = "https://boxd.sh/downloads/cli/boxd-linux-arm64";
      hash = "sha256-TVCIe9i6AdfltOBGiGWbpor0lPNX40sK3Xt35IJWOeE=";
    };
    aarch64-darwin = {
      url = "https://boxd.sh/downloads/cli/boxd-darwin-arm64";
      hash = "sha256-rSJjp67z+yES7DGDiUIKpi6jThGpN7nb8UwuOJ4zAT4=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system} or (throw "boxd: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "boxd";
  version = "0.1.23";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/boxd
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/boxd";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "CLI for boxd cloud VMs — create, fork, exec, and manage remote Linux machines";
    homepage = "https://boxd.sh";
    changelog = "https://docs.boxd.sh";
    # Binary-only distribution; no open-source license published with the CLI.
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "boxd";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
