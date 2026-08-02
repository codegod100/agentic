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
      url = "https://github.com/pullrun/pullrun/releases/download/v0.7.9/pullrun-0.7.9-linux-amd64.tar.gz";
      hash = "sha256-NE3Ch5XH7VsLgKiCJnHqwzV9c3HurXfa83eqBCJN1l8=";
    };
    aarch64-linux = {
      url = "https://github.com/pullrun/pullrun/releases/download/v0.7.9/pullrun-0.7.9-linux-arm64.tar.gz";
      hash = "sha256-jFy57LRxabOWCQnJTyABTb3IzHl0oHDD+r6gp5ox2Z8=";
    };
    x86_64-darwin = {
      url = "https://github.com/pullrun/pullrun/releases/download/v0.7.9/pullrun-0.7.9-darwin-amd64.tar.gz";
      hash = "sha256-tqWty9CjMTRd2v3veVz+SG+LUpnP8qgalF2f20l2AL0=";
    };
    aarch64-darwin = {
      url = "https://github.com/pullrun/pullrun/releases/download/v0.7.9/pullrun-0.7.9-darwin-arm64.tar.gz";
      hash = "sha256-/hRQmxJ4/mzX1KVDOeHK7/xDVLcT36FD0uyMnSPsvtw=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "pullrun: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "pullrun";
  version = "0.7.9";

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
