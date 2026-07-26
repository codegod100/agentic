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
  xkeyboard-config,
  versionCheckHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "zed-preview";
  # Official preview channel tags are vX.Y.Z-pre (prerelease on GitHub).
  version = "1.13.0-pre";

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
    # Coexist with nixpkgs zed-editor / zed-editor-fhs (bin + icons + libexec).
    # CLI looks up ../libexec/zed-editor then ../lib/zed/zed-editor (see
    # crates/cli); use the second path so profile install does not collide.
    mv $out/bin/zed $out/bin/zed-preview
    mkdir -p $out/lib/zed
    mv $out/libexec/zed-editor $out/lib/zed/zed-editor
    rmdir $out/libexec

    # Rename icons so share/icons/.../zed.png does not collide with zed-editor.
    find $out/share/icons -type f -name 'zed.png' | while read -r icon; do
      mv "$icon" "$(dirname "$icon")/zed-preview.png"
    done

    # Point the desktop entry at our binary + icon names (line-anchored; plain
    # substitute would also rewrite TryExec when matching Exec=zed).
    sed -i \
      -e 's/^TryExec=zed$/TryExec=zed-preview/' \
      -e 's/^Exec=zed/Exec=zed-preview/' \
      -e 's/^Icon=zed$/Icon=zed-preview/' \
      $out/share/applications/dev.zed.Zed-Preview.desktop

    runHook postInstall
  '';

  postFixup = ''
    # xkbcommon defaults to /usr/share/X11/xkb, which does not exist on NixOS.
    wrapProgram $out/bin/zed-preview \
      --set ZED_UPDATE_EXPLANATION "Zed Preview has been installed using Nix. Auto-updates have thus been disabled." \
      --set XKB_CONFIG_ROOT "${xkeyboard-config}/share/X11/xkb"
    # GUI binary (CLI spawns this via ../lib/zed/zed-editor).
    wrapProgram $out/lib/zed/zed-editor \
      --set ZED_UPDATE_EXPLANATION "Zed Preview has been installed using Nix. Auto-updates have thus been disabled." \
      --set XKB_CONFIG_ROOT "${xkeyboard-config}/share/X11/xkb"
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
