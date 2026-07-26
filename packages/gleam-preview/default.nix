{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
}:

let
  # Prebuilt static (Linux musl) / native (macOS) binaries from GitHub releases.
  # Asset names: gleam-v{version}-{target}.tar.gz — each archive is a single `gleam`.
  sources = {
    x86_64-linux = {
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc1/gleam-v1.18.0-rc1-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-4nCA6pli6Z7O2Uy8A+ffHgnEd2ATBQo/zA+nWFyKqlo=";
    };
    aarch64-linux = {
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc1/gleam-v1.18.0-rc1-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-d3z6GuSUIDEYWweSNZba0Pgxd/88LJ1riwkDbxsrAms=";
    };
    x86_64-darwin = {
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc1/gleam-v1.18.0-rc1-x86_64-apple-darwin.tar.gz";
      hash = "sha256-f1iBXb6djyTGDQ4I2o73j87zqBxFnFuECe9JhjiwAkU=";
    };
    aarch64-darwin = {
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc1/gleam-v1.18.0-rc1-aarch64-apple-darwin.tar.gz";
      hash = "sha256-UYDqJiHrcLnoqPFOavJBa9/RF1dBrxmOPBt6K8g5QCA=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "gleam-preview: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gleam-preview";
  # Official prerelease tags are vX.Y.Z-rcN (and similar) on GitHub.
  version = "1.18.0-rc2";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # Archive root is just the `gleam` binary (no directory wrapper).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    # Install as gleam-preview so this can coexist with nixpkgs gleam on PATH.
    install -Dm755 gleam $out/bin/gleam-preview
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/gleam-preview";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Statically typed language for the Erlang VM (official prerelease binaries)";
    homepage = "https://gleam.run";
    changelog = "https://github.com/gleam-lang/gleam/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "gleam-preview";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
