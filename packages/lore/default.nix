{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
  versionCheckHook,
}:

let
  # Prebuilt CLI from https://github.com/EpicGames/lore/releases.
  # Asset names: lore-v{version}-{target}.tar.gz
  # Platforms match the official install.sh triple matrix (no darwin-x86_64;
  # aarch64-linux is the Graviton/Neoverse 512-tvb build upstream ships).
  sources = {
    x86_64-linux = {
      url = "https://github.com/EpicGames/lore/releases/download/v0.8.5/lore-v0.8.5-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-PVi9NsquwumRZInsfk/HGVqFjlHLcaO26Q1yrf4wYv8=";
    };
    aarch64-linux = {
      url = "https://github.com/EpicGames/lore/releases/download/v0.8.5/lore-v0.8.5-aarch64-unknown-linux-gnu-neoverse-512tvb.tar.gz";
      hash = "sha256-xvxH0PoHBvjZedA5pmW8f7Xteooj6eaavNnKsFJ4ETQ=";
    };
    aarch64-darwin = {
      url = "https://github.com/EpicGames/lore/releases/download/v0.8.5/lore-v0.8.5-aarch64-apple-darwin.tar.gz";
      hash = "sha256-+6Tq+xI6/lmbXXUhIftqXaci8zsqPaM5AyS2VNMdx00=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "lore: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "lore";
  version = "0.8.5";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # Archive root: lore + LICENSE.txt + THIRD-PARTY-NOTICES.txt
  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libgcc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 lore $out/bin/lore
    install -Dm644 LICENSE.txt $out/share/licenses/lore/LICENSE.txt
    install -Dm644 THIRD-PARTY-NOTICES.txt $out/share/licenses/lore/THIRD-PARTY-NOTICES.txt
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/lore";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Next-generation open source version control system (Epic Games)";
    homepage = "https://github.com/EpicGames/lore";
    changelog = "https://github.com/EpicGames/lore/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "lore";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
