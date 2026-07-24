{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
}:

let
  # Prebuilt release tarballs from https://github.com/pullrun/pullrun/releases.
  # Each archive has pullrun-{os}-{arch} + pullrun-runtime-{os}-{arch} (static).
  sources = {
    x86_64-linux = {
      url = "https://github.com/pullrun/pullrun/releases/download/v0.6.7/pullrun-0.6.7-linux-amd64.tar.gz";
      hash = "sha256-aFIa59shNN+Ptt8vd39fRvY1Gjh5WghZLrAc7lmRtkw=";
    };
    aarch64-linux = {
      url = "https://github.com/pullrun/pullrun/releases/download/v0.6.7/pullrun-0.6.7-linux-arm64.tar.gz";
      hash = "sha256-Ct0fm26gMwqx9tw96X8TW5xnUZpwC9HXgzn5tDr7cy4=";
    };
    x86_64-darwin = {
      url = "https://github.com/pullrun/pullrun/releases/download/v0.6.7/pullrun-0.6.7-darwin-amd64.tar.gz";
      hash = "sha256-f9xQJcH5CpcwbHSOZg7K7fWdRjipUkiYMCywbGQ025c=";
    };
    aarch64-darwin = {
      url = "https://github.com/pullrun/pullrun/releases/download/v0.6.7/pullrun-0.6.7-darwin-arm64.tar.gz";
      hash = "sha256-tj1K0VKI2UnWUT8lqTiXC9MD4qM8R4iYy/AoNBLTr/8=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "pullrun: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "pullrun";
  version = "0.6.7";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # Archive root is the two platform-suffixed binaries (no directory wrapper).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    for f in pullrun-*; do
      case "$f" in
        pullrun-runtime-*)
          install -Dm755 "$f" $out/bin/pullrun-runtime
          ;;
        pullrun-*)
          install -Dm755 "$f" $out/bin/pullrun
          ;;
      esac
    done
    test -x $out/bin/pullrun
    test -x $out/bin/pullrun-runtime
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/pullrun";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Container runtime with zero-copy DAG storage — run OCI images as containers, Firecracker microVMs, or Apple Silicon VMs";
    homepage = "https://github.com/pullrun/pullrun";
    changelog = "https://github.com/pullrun/pullrun/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "pullrun";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
