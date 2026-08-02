{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
  versionCheckHook,
}:

let
  # Prebuilt CLI binaries published to npm as @rsvelte/lint-<triple>.
  # Tarball root is package/rsvelte-lint (+ optional .node addon unused here).
  sources = {
    x86_64-linux = {
      url = "https://registry.npmjs.org/@rsvelte/lint-linux-x64-gnu/-/lint-linux-x64-gnu-0.10.3.tgz";
      hash = "sha256-Y6A5drhkmuxMvRkiedriajTJFuK7hrnTd3x202tVaxw=";
    };
    aarch64-linux = {
      url = "https://registry.npmjs.org/@rsvelte/lint-linux-arm64-gnu/-/lint-linux-arm64-gnu-0.10.3.tgz";
      hash = "sha256-HTRng7nhRUbISi1VEvKttzaCNyU7GUXGvN7gtg0y5Fg=";
    };
    x86_64-darwin = {
      url = "https://registry.npmjs.org/@rsvelte/lint-darwin-x64/-/lint-darwin-x64-0.10.3.tgz";
      hash = "sha256-hLQ5PhSb8Tei9RUpNDO7qt2l5qQZ3CLUZOPbBh3v99w=";
    };
    aarch64-darwin = {
      url = "https://registry.npmjs.org/@rsvelte/lint-darwin-arm64/-/lint-darwin-arm64-0.10.3.tgz";
      hash = "sha256-bJuW8TFFDbpeamET+zkbxj5pkqfSCv63iXa8l6r4XLA=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "rsvelte-lint: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rsvelte-lint";
  version = "0.10.3";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # npm tarball root: package/rsvelte-lint
  sourceRoot = "package";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libgcc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 rsvelte-lint $out/bin/rsvelte-lint
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/rsvelte-lint";
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Rust-powered native Svelte linter CLI (rsvelte)";
    homepage = "https://github.com/baseballyama/rsvelte";
    changelog = "https://github.com/baseballyama/rsvelte/releases/tag/@rsvelte/lint@${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "rsvelte-lint";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
