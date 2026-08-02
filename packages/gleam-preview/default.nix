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
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc2/gleam-v1.18.0-rc2-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-9lcProE0cVc0T9lIGPZ1TL/IUn12FvTtnaytocYyTII=";
    };
    aarch64-linux = {
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc2/gleam-v1.18.0-rc2-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-vynJu5dTDwl66eQJpkVMD9MTp/k+f0KucJopM/LTDaA=";
    };
    x86_64-darwin = {
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc2/gleam-v1.18.0-rc2-x86_64-apple-darwin.tar.gz";
      hash = "sha256-y4pFm1evSL943a0zyRlPJxEqOOs/VT+5x9oEONvad6U=";
    };
    aarch64-darwin = {
      url = "https://github.com/gleam-lang/gleam/releases/download/v1.18.0-rc2/gleam-v1.18.0-rc2-aarch64-apple-darwin.tar.gz";
      hash = "sha256-9AG5pV0CXWHQsTmTvIAk5BCT1sTu8qxI2TsLxHhxczY=";
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
