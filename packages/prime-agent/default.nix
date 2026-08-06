{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  python3,
  python312,
  cmake,
  pkg-config,
  cacert,
  makeWrapper,
}:

let
  # Managed kernel Python for PRIME_AGENT_KERNEL_PYTHON. Upstream bootstrap.ts
  # defaults to Python 3.11; nixpkgs ipykernel is unavailable on 3.11 (sphinx),
  # so we use 3.12. Bundles ipykernel, prime-agent-runtime (from the release
  # pack's dist/), dill, and DEFAULT_RLM_EXTRA_PACKAGES so first launch does
  # not need uv/network to seed ~/.prime/agent/kernel-venv.
  kernelPythonFor =
    version: src:
    let
      # nixpkgs tyro's pytest suite hits sandbox chdir failures in this env;
      # we only need the importable library for the kernel.
      python = python312.override {
        packageOverrides = _self: super: {
          tyro = super.tyro.overridePythonAttrs (_: {
            doCheck = false;
          });
        };
      };

      prime-agent-runtime = python.pkgs.buildPythonPackage {
        pname = "prime-agent-runtime";
        inherit version src;
        pyproject = true;

        # Bundled in the npm pack next to the JS dist.
        sourceRoot = "package/dist/prime-agent-runtime";

        build-system = [ python.pkgs.hatchling ];

        dependencies = with python.pkgs; [
          ipykernel
          nest-asyncio
          tyro
        ];

        # Upstream ships tests, but they need a live host/kernel; import check is enough.
        doCheck = false;
        pythonImportsCheck = [ "rlm" ];

        meta = {
          description = "Kernel-side runtime shim for Prime Agent recursion";
          homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
          license = lib.licenses.mit;
        };
      };
    in
    python.withPackages (
      ps: with ps; [
        ipykernel
        nest-asyncio
        tyro
        dill
        requests
        httpx
        pyyaml
        tomli
        python-dotenv
        pandas
        numpy
        scipy
        beautifulsoup4
        lxml
        pydantic
        prime-agent-runtime
      ]
    );
in
buildNpmPackage.override { nodejs = nodejs_22; } (finalAttrs: {
  pname = "prime-agent";
  version = "0.7.0";

  # Official prebuilt npm pack from GitHub Releases (includes dist/ + Python runtime).
  # Sibling workspace packages are pulled in as upstream R2 CDN URL deps.
  src = fetchurl {
    url = "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${finalAttrs.version}/prime-agent-${finalAttrs.version}.tgz";
    hash = "sha256-iLZXhRjHLNUaglvIDyjg/vmmTGfeSn1v16/Xyhs02gs=";
  };

  # npm pack layout
  sourceRoot = "package";

  # Vendored lock with resolved URLs (release tarball ships none).
  # Sibling @earendil-works/* packages resolve via upstream's R2 CDN URLs
  # (same bytes as the GitHub release assets).
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-hs/Fe8GrR1DOncpN0C0Z5ruDC8kDYICMH/dCAV84ylA=";

  # npm needs a writable cache when installing URL/GitHub tarball deps.
  makeCacheWritable = true;

  # Prebuilt JS; only need to install/link deps (incl. zeromq native addon).
  dontNpmBuild = true;
  dontBuild = true;

  # cmake/pkg-config are only on PATH for zeromq's cmake-ts install script;
  # do not run a top-level CMake configure against the npm pack.
  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    python3
    cmake
    pkg-config
    makeWrapper
  ];

  # zeromq's cmake-ts install fetches/builds native code and needs CA certs.
  env = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NODE_OPTIONS = "--use-openssl-ca";
  };

  # Skip uv bootstrap; users can still override PRIME_AGENT_KERNEL_PYTHON.
  postFixup = ''
    wrapProgram $out/bin/prime-agent \
      --set-default PRIME_AGENT_KERNEL_PYTHON "${
        kernelPythonFor finalAttrs.version finalAttrs.src
      }/bin/python"
  '';

  passthru = {
    kernelPython = kernelPythonFor finalAttrs.version finalAttrs.src;
  };

  meta = {
    description = "Self-improving RLM agent for coding workflows and long-running autonomous tasks";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "prime-agent";
    platforms = lib.platforms.unix;
    longDescription = ''
      Wraps the upstream CLI with PRIME_AGENT_KERNEL_PYTHON pointing at a Nix-built
      Python 3.12 environment (ipykernel, prime-agent-runtime, and the default RLM
      packages) so the IPython control kernel works offline without uv seeding
      ~/.prime/agent/kernel-venv.
    '';
  };
})
