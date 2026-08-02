{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
  versionCheckHook,
}:

let
  # Prebuilt CLI binaries published to npm as @rsvelte/fmt-<triple>.
  # Tarball root is package/rsvelte-fmt (npm pack layout).
  sources = {
    x86_64-linux = {
      url = "https://registry.npmjs.org/@rsvelte/fmt-linux-x64-gnu/-/fmt-linux-x64-gnu-0.7.6.tgz";
      hash = "sha256-ednlCLowE9pE2UFdcH91PlOhG1ttRVR85yuPLKTDhDk=";
    };
    aarch64-linux = {
      url = "https://registry.npmjs.org/@rsvelte/fmt-linux-arm64-gnu/-/fmt-linux-arm64-gnu-0.7.6.tgz";
      hash = "sha256-Vz+lBYjQ5UnrjAzgJRIiAkA2nvAaEaNaVPvQxPHpSjE=";
    };
    x86_64-darwin = {
      url = "https://registry.npmjs.org/@rsvelte/fmt-darwin-x64/-/fmt-darwin-x64-0.7.6.tgz";
      hash = "sha256-0XG7zsCAHsHRE30+DVukcQIwNhFkpAuV7H6AgWfR41Q=";
    };
    aarch64-darwin = {
      url = "https://registry.npmjs.org/@rsvelte/fmt-darwin-arm64/-/fmt-darwin-arm64-0.7.6.tgz";
      hash = "sha256-yHB04WrgnHCuramVgFGVMdnZD+Mlm5kzaVv0X0oGx9s=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "rsvelte-fmt: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rsvelte-fmt";
  version = "0.7.6";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # npm tarball root: package/rsvelte-fmt
  sourceRoot = "package";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libgcc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 rsvelte-fmt $out/bin/rsvelte-fmt
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/rsvelte-fmt";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Rust-powered Svelte + JS/TS/CSS formatter CLI (rsvelte)";
    homepage = "https://github.com/baseballyama/rsvelte";
    changelog = "https://github.com/baseballyama/rsvelte/releases/tag/@rsvelte/fmt@${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "rsvelte-fmt";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
