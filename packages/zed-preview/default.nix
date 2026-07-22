{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  libGL,
  libgcc,
  vulkan-loader,
  wayland,
  versionCheckHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "zed-preview";
  # Official preview channel tags are vX.Y.Z-pre (prerelease on GitHub).
  version = "1.12.0-pre";

  src = fetchurl {
    url = "https://github.com/zed-industries/zed/releases/download/v${finalAttrs.version}/zed-linux-x86_64.tar.gz";
    hash = "sha256-KqqXibrYxLzt+HInAJla86wbqgVlDE4PKLha6BOflgc=";
  };

  sourceRoot = "zed-preview.app";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    libgcc
  ];

  # Bundled $ORIGIN/../lib covers most deps; these are either NEEDED (alsa) or
  # commonly dlopened at runtime (GPU / Wayland).
  runtimeDependencies = [
    alsa-lib
    libGL
    vulkan-loader
    wayland
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -a bin lib libexec share $out/
    # Coexist with nixpkgs zed-editor (zeditor) and a stable zed binary.
    mv $out/bin/zed $out/bin/zed-preview

    # Point the desktop entry at our binary name (line-anchored; plain
    # substitute would also rewrite TryExec when matching Exec=zed).
    sed -i \
      -e 's/^TryExec=zed$/TryExec=zed-preview/' \
      -e 's/^Exec=zed/Exec=zed-preview/' \
      $out/share/applications/dev.zed.Zed-Preview.desktop

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/zed-preview \
      --set ZED_UPDATE_EXPLANATION "Zed Preview has been installed using Nix. Auto-updates have thus been disabled."
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/zed-preview";
  versionCheckProgramArg = "--version";
  # Upstream prints "Zed preview 1.12.0 <sha> …" (no -pre suffix).
  preInstallCheck = ''
    export version="${lib.removeSuffix "-pre" finalAttrs.version}"
  '';
  doInstallCheck = true;

  meta = {
    description = "High-performance, multiplayer code editor (official Linux preview binaries)";
    homepage = "https://zed.dev";
    changelog = "https://github.com/zed-industries/zed/releases/tag/v${finalAttrs.version}";
    # AGPL for the editor; some bundled components differ — see licenses.md in the tarball.
    license = lib.licenses.gpl3Only;
    mainProgram = "zed-preview";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
