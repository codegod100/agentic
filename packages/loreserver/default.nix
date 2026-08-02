{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
  versionCheckHook,
}:

let
  # Prebuilt server from https://github.com/EpicGames/lore/releases.
  # Asset names: loreserver-v{version}-{target}.tar.gz
  # Platforms match the official install.sh triple matrix (no darwin-x86_64;
  # aarch64-linux is the Graviton/Neoverse 512-tvb build upstream ships).
  sources = {
    x86_64-linux = {
      url = "https://github.com/EpicGames/lore/releases/download/v0.8.6/loreserver-v0.8.6-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-8N6ExhdaR28Vd1T1cxa+A0YQW+UCyT+rtlu5COqw4eE=";
    };
    aarch64-linux = {
      url = "https://github.com/EpicGames/lore/releases/download/v0.8.6/loreserver-v0.8.6-aarch64-unknown-linux-gnu-neoverse-512tvb.tar.gz";
      hash = "sha256-Aamr+HZDxGwQ2f19Mbs8kfNxtLZtZsOd+DhgTOTpwVE=";
    };
    aarch64-darwin = {
      url = "https://github.com/EpicGames/lore/releases/download/v0.8.6/loreserver-v0.8.6-aarch64-apple-darwin.tar.gz";
      hash = "sha256-SCgfzPcu07pK0ycRdVI1lQaSlfTzC5NuuxXC+lAZnks=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "loreserver: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "loreserver";
  version = "0.8.6";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # Archive root: loreserver + LICENSE.txt + THIRD-PARTY-NOTICES.txt
  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libgcc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 loreserver $out/bin/loreserver
    install -Dm644 LICENSE.txt $out/share/licenses/loreserver/LICENSE.txt
    install -Dm644 THIRD-PARTY-NOTICES.txt $out/share/licenses/loreserver/THIRD-PARTY-NOTICES.txt
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/loreserver";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Lore version-control server (Epic Games)";
    homepage = "https://github.com/EpicGames/lore";
    changelog = "https://github.com/EpicGames/lore/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "loreserver";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
