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
  gettext,
  glib,
  gtk3,
  gtk4,
  libadwaita,
}:

python3.pkgs.buildPythonApplication (finalAttrs: {
  pname = "portfolio";
  version = "1.0.3";
  # Built with meson, not a Python packaging format.
  pyproject = false;

  src = fetchFromGitHub {
    owner = "tchx84";
    repo = "Portfolio";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KlFRgBXEoIF/UqZKSAC/oQ+OQBrl40NIXV+49jBq430=";
  };

  postPatch = ''
    patchShebangs build-aux/meson
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gobject-introspection
    wrapGAppsHook4
    appstream-glib
    desktop-file-utils
    gettext
    # glib-compile-schemas / gtk-update-icon-cache (meson post_install).
    glib
    gtk3
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

  postInstall = ''
    ln -s dev.tchx84.Portfolio "$out/bin/portfolio"
  '';

  # Prevent double wrapping.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
  '';

  meta = {
    description = "Minimalist file manager for those who want to use Linux mobile devices";
    homepage = "https://github.com/tchx84/Portfolio";
    changelog = "https://github.com/tchx84/Portfolio/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.gpl3Plus;
    mainProgram = "dev.tchx84.Portfolio";
    platforms = lib.platforms.linux;
  };
})
