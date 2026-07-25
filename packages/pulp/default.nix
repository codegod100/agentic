{
  lib,
  python3,
  fetchFromGitLab,
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
  libsecret,
  webkitgtk_6_0,
}:

python3.pkgs.buildPythonApplication (finalAttrs: {
  pname = "pulp";
  version = "2026.4";
  # Built with meson, not a Python packaging format.
  pyproject = false;

  src = fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "cheywood";
    repo = "Pulp";
    tag = finalAttrs.version;
    hash = "sha256-jw7tGA9baSSJEspOGQq2VIzPDHWc1PNv5gBRtSz4d/w=";
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
    libsecret
    webkitgtk_6_0
  ];

  dependencies = with python3.pkgs; [
    pygobject3
    requests
    beautifulsoup4
    cairosvg
    lxml
    pillow
  ];

  # Prevent double wrapping.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
  '';

  meta = {
    description = "RSS reader focused on clearing a large volume of articles efficiently";
    homepage = "https://gitlab.gnome.org/cheywood/Pulp";
    changelog = "https://gitlab.gnome.org/cheywood/Pulp/-/blob/${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.gpl3Plus;
    mainProgram = "pulp";
    platforms = lib.platforms.linux;
  };
})
