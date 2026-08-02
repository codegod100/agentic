{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
}:

let
  # Prebuilt CLI binaries published to npm as @rsvelte/svelte-check-<triple>.
  # Upstream binary filename is `svelte-check`; we install as `rsvelte-check`
  # to match the npm bin name and avoid colliding with JS svelte-check.
  sources = {
    x86_64-linux = {
      url = "https://registry.npmjs.org/@rsvelte/svelte-check-linux-x64-gnu/-/svelte-check-linux-x64-gnu-0.5.9.tgz";
      hash = "sha256-ZCCmrygYSYt/6JCzeyskOuV8AWQ/7ezDO7W5UV1x5k0=";
    };
    aarch64-linux = {
      url = "https://registry.npmjs.org/@rsvelte/svelte-check-linux-arm64-gnu/-/svelte-check-linux-arm64-gnu-0.5.9.tgz";
      hash = "sha256-oWrUgtpE3iuf5jB+bEQq95M4iS8ItnrL2/8K1Pr8U4k=";
    };
    x86_64-darwin = {
      url = "https://registry.npmjs.org/@rsvelte/svelte-check-darwin-x64/-/svelte-check-darwin-x64-0.5.9.tgz";
      hash = "sha256-tqfHnnqVmGveQx8J08z0BHDR4Bx3e3L3JmxFUJSvhw0=";
    };
    aarch64-darwin = {
      url = "https://registry.npmjs.org/@rsvelte/svelte-check-darwin-arm64/-/svelte-check-darwin-arm64-0.5.9.tgz";
      hash = "sha256-AjSoLl+bz9cb+BjVPfAdsiAAeTuPGR7FtVqg8H3mKiI=";
    };
  };

  srcAttrs =
    sources.${stdenv.hostPlatform.system}
      or (throw "rsvelte-check: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rsvelte-check";
  version = "0.5.9";

  src = fetchurl {
    inherit (srcAttrs) url hash;
  };

  # npm tarball root: package/svelte-check
  sourceRoot = "package";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libgcc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 svelte-check $out/bin/rsvelte-check
    runHook postInstall
  '';

  # Upstream CLI has no --version flag; smoke-test --help instead.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/rsvelte-check" --help | grep -q 'Type-check'
    runHook postInstallCheck
  '';

  meta = {
    description = "Rust-powered svelte-check-compatible CLI (rsvelte)";
    homepage = "https://github.com/baseballyama/rsvelte";
    changelog = "https://github.com/baseballyama/rsvelte/releases/tag/@rsvelte/svelte-check@${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "rsvelte-check";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
