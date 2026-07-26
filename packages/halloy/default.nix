{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  libgcc,
  libGL,
  libxkbcommon,
  libxcb,
  libX11,
  libXcursor,
  libXi,
  vulkan-loader,
  wayland,
  xkeyboard-config,
  versionCheckHook,
}:

let
  # Official prebuilt Linux x86_64 tarball from GitHub releases.
  # Asset: halloy-{version}-x86_64-linux.tar.gz (bin + desktop + icons).
  sources = {
    x86_64-linux = {
      url = "https://github.com/squidowl/halloy/releases/download/2026.8/halloy-2026.8-x86_64-linux.tar.gz";
      hash = "sha256-bw8R3MstC0DegSgSGF/ERDhrFl2UPgK5S3tKHiCVgFc=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "halloy: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "halloy";
  version = "2026.8";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # Archive root: bin/halloy + share/{applications,icons,metainfo}
  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    libgcc
    libxcb
  ];

  # iced/wgpu commonly dlopens GPU / Wayland / X11 at runtime.
  runtimeDependencies = [
    alsa-lib
    libGL
    libxkbcommon
    libxcb
    libX11
    libXcursor
    libXi
    vulkan-loader
    wayland
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a bin share $out/
    runHook postInstall
  '';

  postFixup = ''
    # xkbcommon defaults to /usr/share/X11/xkb, which does not exist on NixOS.
    wrapProgram $out/bin/halloy \
      --set XKB_CONFIG_ROOT "${xkeyboard-config}/share/X11/xkb"
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/halloy";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "IRC client written in Rust";
    homepage = "https://github.com/squidowl/halloy";
    changelog = "https://github.com/squidowl/halloy/blob/${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.gpl3Only;
    mainProgram = "halloy";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
