{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
  versionCheckHook,
  symlinkJoin,
}:

let
  # Prebuilt CLIs from https://github.com/baseballyama/rsvelte, published to
  # npm as @rsvelte/<tool>-<triple>. Each tool versions independently.
  mkCli =
    {
      pname,
      version,
      sources,
      # Binary filename inside the npm tarball (under package/).
      srcBin,
      # Installed $out/bin name (defaults to pname).
      bin ? pname,
      # Optional installCheckPhase body (runs after hooks). Prefer this when
      # the CLI has no --version (e.g. rsvelte-check).
      installCheck ? null,
    }:
    let
      srcAttrs =
        sources.${stdenv.hostPlatform.system}
          or (throw "${pname}: unsupported system ${stdenv.hostPlatform.system}");
    in
    stdenv.mkDerivation (
      {

        inherit pname version;

        src = fetchurl {
          inherit (srcAttrs) url hash;
        };

        # npm tarball root: package/<binary>
        sourceRoot = "package";

        nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

        buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libgcc ];

        installPhase = ''
          runHook preInstall
          install -Dm755 ${srcBin} $out/bin/${bin}
          runHook postInstall
        '';

        doInstallCheck = true;

        meta = {
          homepage = "https://github.com/baseballyama/rsvelte";
          license = lib.licenses.mit;
          mainProgram = bin;
          platforms = builtins.attrNames sources;
          sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
        };
      }
      // lib.optionalAttrs (installCheck == null) {
        nativeInstallCheckInputs = [ versionCheckHook ];
        versionCheckProgram = "${placeholder "out"}/bin/${bin}";
        versionCheckProgramArg = "--version";
      }
      // lib.optionalAttrs (installCheck != null) {
        installCheckPhase = ''
          runHook preInstallCheck
          ${installCheck}
          runHook postInstallCheck
        '';
      }
    );

  fmt = mkCli {
    pname = "rsvelte-fmt";
    version = "0.7.6";
    srcBin = "rsvelte-fmt";
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
  };

  lint = mkCli {
    pname = "rsvelte-lint";
    version = "0.10.3";
    srcBin = "rsvelte-lint";
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
  };

  check = mkCli {
    pname = "rsvelte-check";
    version = "0.5.9";
    # Upstream binary filename is `svelte-check`; install as `rsvelte-check`
    # to match the npm bin name and avoid colliding with JS svelte-check.
    srcBin = "svelte-check";
    bin = "rsvelte-check";
    installCheck = ''
      "$out/bin/rsvelte-check" --help | grep -q 'Type-check'
    '';
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
  };
in
symlinkJoin {
  pname = "rsvelte";
  name = "rsvelte";
  paths = [
    fmt
    lint
    check
  ];

  passthru = {
    inherit fmt lint check;
  };

  meta = {
    description = "Rust-powered Svelte tooling CLIs (fmt, lint, check)";
    homepage = "https://github.com/baseballyama/rsvelte";
    license = lib.licenses.mit;
    # No single primary binary; apps.* expose each CLI.
    platforms = lib.unique (
      fmt.meta.platforms ++ lint.meta.platforms ++ check.meta.platforms
    );
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
