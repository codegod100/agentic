{
  lib,
  stdenv,
  fetchurl,
  runtimeShell,
}:

let
  # Prebuilt CLI binaries from https://github.com/CrowdHailer/eyg-lang/releases
  # (tag gleam_cli-v{version}). Asset names match install.sh: eyg-{os}-{arch}.
  # Plain executable files (not tarballs); Linux builds are dynamic glibc.
  sources = {
    x86_64-linux = {
      url = "https://github.com/CrowdHailer/eyg-lang/releases/download/gleam_cli-v0.0.2/eyg-linux-x64";
      hash = "sha256-gSjCXY1CSmgFG1XV4/dr4Xpz4CoXwqkcNpylPaPKeOI=";
    };
    aarch64-linux = {
      url = "https://github.com/CrowdHailer/eyg-lang/releases/download/gleam_cli-v0.0.2/eyg-linux-arm64";
      hash = "sha256-rLgjnG92nhzfUAhuW2k/9M2sgMl2ytUxgWzC3icMyZg=";
    };
    x86_64-darwin = {
      url = "https://github.com/CrowdHailer/eyg-lang/releases/download/gleam_cli-v0.0.2/eyg-macos-x64";
      hash = "sha256-aYhTB+Z+WrwwwuLh7PwHd8H1EESsS0hAF5Sts1d0hNQ=";
    };
    aarch64-darwin = {
      url = "https://github.com/CrowdHailer/eyg-lang/releases/download/gleam_cli-v0.0.2/eyg-macos-arm64";
      hash = "sha256-zbwBhw1kS1DtXRxyD7WMmt9k7jf4HPxHBNKcKG1EsHE=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "eyg: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "eyg";
  # Release tags are gleam_cli-vX.Y.Z (not the binary's self-reported version).
  version = "0.0.2";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  dontUnpack = true;

  # Bun `build --compile` embeds the JS payload by absolute file offset.
  # autoPatchelf/patchelf rewrites the ELF (longer INTERP, shifted sections)
  # and shifts those offsets → SIGSEGV / core dump at runtime. Leave the
  # binary byte-identical and run it via the nix dynamic linker instead.
  dontStrip = true;
  dontPatchELF = true;

  installPhase =
    if stdenv.hostPlatform.isLinux then
      ''
        runHook preInstall
        install -Dm755 $src $out/libexec/eyg
        mkdir -p $out/bin
        cat > $out/bin/eyg <<EOF
        #!${runtimeShell}
        # Do not rewrite the Bun-compiled ELF; exec through the dynamic linker.
        exec ${stdenv.cc.bintools.dynamicLinker} $out/libexec/eyg "\$@"
        EOF
        chmod +x $out/bin/eyg
        runHook postInstall
      ''
    else
      ''
        runHook preInstall
        # macOS binaries are not Bun-ELF/patchelf-sensitive the same way.
        install -Dm755 $src $out/bin/eyg
        runHook postInstall
      '';

  # Binary self-reports "eyg 0.0.0" (not the release tag), so skip versionCheckHook.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    result=$("$out/bin/eyg" eval -c '!int_add(1, 1)')
    test "$result" = "2"
    runHook postInstallCheck
  '';

  meta = {
    description = "EYG (Eat Your Greens) — safest scripting language with structural typing and managed effects";
    homepage = "https://github.com/CrowdHailer/eyg-lang";
    changelog = "https://github.com/CrowdHailer/eyg-lang/releases/tag/gleam_cli-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "eyg";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
