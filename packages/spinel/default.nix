{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  libxcrypt,
  makeWrapper,
}:

let
  # Keep in sync with PRISM_VERSION / RBS_VERSION in upstream Makefile.
  # `make deps` downloads these from rubygems.org; we vendor them so the
  # build stays offline/pure.
  prismVersion = "1.9.0";
  rbsVersion = "4.0.1";

  prismGem = fetchurl {
    url = "https://rubygems.org/gems/prism-${prismVersion}.gem";
    hash = "sha256-e1MMap+SwkMAAUkZydy8BVv0zfUewwrtCZsGzWZ074U=";
  };

  rbsGem = fetchurl {
    url = "https://rubygems.org/gems/rbs-${rbsVersion}.gem";
    hash = "sha256-4jf9SXh/smW/DzifLw9XiP3N8fSbtUtPeVLOqQQWKgc=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "spinel";
  # No upstream tags yet — date-stamped unstable version of a pinned commit.
  version = "0-unstable-2026-07-20";

  src = fetchFromGitHub {
    owner = "matz";
    repo = "spinel";
    rev = "99aad26b59ec134596833b101cb1c03909afd130";
    hash = "sha256-Dqaopg08gqBH++Uc9HZi0LqhwwaHNLn6eX5x0jXlYDo=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # String#crypt = libcrypt(3); glibc keeps it in a separate DSO on modern
  # Linux. Upstream Makefile adds -lcrypt only on Linux.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libxcrypt ];

  postPatch = ''
    # Embed a meaningful `spinel --version` without needing .git in the sandbox.
    substituteInPlace Makefile \
      --replace-fail \
        'r=$$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)' \
        'r=${builtins.substring 0 12 finalAttrs.src.rev}'

    # Vendor libprism + rbs C sources (normally `make deps`).
    mkdir -p vendor/prism vendor/rbs
    tmp=$(mktemp -d)
    tar -xf ${prismGem} -C "$tmp" data.tar.gz
    tar -xzf "$tmp/data.tar.gz" -C vendor/prism
    rm -rf "$tmp"
    tmp=$(mktemp -d)
    tar -xf ${rbsGem} -C "$tmp" data.tar.gz
    tar -xzf "$tmp/data.tar.gz" -C vendor/rbs
    rm -rf "$tmp"
    test -f vendor/prism/include/prism/diagnostic.h
    test -f vendor/rbs/include/rbs/parser.h
  '';

  # Don't wrap CC with sccache/ccache if present on the host.
  makeFlags = [
    "NO_CCACHE=1"
    "PREFIX=${placeholder "out"}"
  ];

  enableParallelBuilding = true;

  # `make install` builds `all` + `bin/spin` first (spin is self-hosted via spinel).
  installFlags = [ "PREFIX=${placeholder "out"}" ];

  # spinel shells out to `cc` to link generated C; keep the stdenv toolchain
  # on PATH. On Linux the generated link line includes -lcrypt (String#crypt),
  # so libxcrypt must be visible to that cc invocation too.
  # Runtime libs/headers resolve via /proc/self/exe → $out/lib/spinel/{lib,packages}.
  postInstall =
    let
      cryptFlags = lib.optionalString stdenv.hostPlatform.isLinux ''
        --prefix NIX_LDFLAGS " " "-L${lib.getLib libxcrypt}/lib" \
        --prefix LIBRARY_PATH : "${lib.getLib libxcrypt}/lib" \
      '';
    in
    ''
      for b in spinel spin spinel-doctor spinel-reduce spinel-flatten; do
        if [ -x "$out/bin/$b" ]; then
          wrapProgram "$out/bin/$b" \
            --prefix PATH : ${lib.makeBinPath [ stdenv.cc ]} \
            ${cryptFlags}
        fi
      done
    '';

  meta = {
    description = "Ruby AOT compiler — whole-program type inference to standalone native binaries";
    homepage = "https://github.com/matz/spinel";
    license = lib.licenses.mit;
    mainProgram = "spinel";
    platforms = lib.platforms.unix;
    # Native Windows is unsupported upstream (POSIX runtime, pthread, etc.).
  };
})
