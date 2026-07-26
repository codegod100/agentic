{
  lib,
  python3,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  gobject-introspection,
  wrapGAppsHook4,
  appstream-glib,
  desktop-file-utils,
  blueprint-compiler,
  glib,
  gtk4,
  libadwaita,
}:

python3.pkgs.buildPythonApplication (finalAttrs: {
  pname = "mimic";
  version = "1.1.4";
  # Built with meson, not a Python packaging format.
  pyproject = false;

  src = fetchFromGitHub {
    owner = "ArijanJ";
    repo = "Mimic";
    tag = "v${finalAttrs.version}";
    hash = "sha256-YBUmAJZWcv3WRAyHkHg59eRQTLC9CXr7BBKegQo7aLY=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gobject-introspection
    wrapGAppsHook4
    appstream-glib
    desktop-file-utils
    blueprint-compiler
    # glib-compile-schemas / gtk-update-icon-cache (meson post_install).
    glib
    gtk4
  ];

  buildInputs = [
    glib
    gtk4
    libadwaita
  ];

  dependencies = with python3.pkgs; [
    pygobject3
  ];

  # Prevent double wrapping.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
  '';

  meta = {
    description = "GTK4 + Adwaita application for managing default apps on Linux";
    homepage = "https://github.com/ArijanJ/Mimic";
    changelog = "https://github.com/ArijanJ/Mimic/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl2Plus;
    mainProgram = "mimic";
    platforms = lib.platforms.linux;
  };
})
