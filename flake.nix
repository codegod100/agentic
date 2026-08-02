{
  description = "Nix packages for third-party projects that don't ship their own flakes";

  nixConfig = {
    extra-substituters = [ "https://codegod100.cachix.org" ];
    extra-trusted-public-keys = [
      "codegod100.cachix.org-1:LZFL5VrR644WUjleS3bLbVeOdzlXqzKznQWvD5MVthA="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # boxd is a binary-only redistributable CLI (unfreeRedistributable).
          # Import a pkgs set that only allows that attr so `nix build .#boxd`
          # works without a global allowUnfree.
          pkgsUnfree = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "boxd" ];
          };
        in
        {
          vit = pkgs.callPackage ./packages/vit { };
          spinel = pkgs.callPackage ./packages/spinel { };
          rook = pkgs.callPackage ./packages/rook { };
          whetuu = pkgs.callPackage ./packages/whetuu { };
          pullrun = pkgs.callPackage ./packages/pullrun { };
          gleam-preview = pkgs.callPackage ./packages/gleam-preview { };
          # Official prebuilt EYG CLI (linux + darwin; dynamic glibc on Linux).
          eyg = pkgs.callPackage ./packages/eyg { };
          # Wrapper around scripts/update-packages.sh (needs a writable checkout).
          update = pkgs.callPackage ./packages/update { };
          default = self.packages.${system}.vit;
        }
        // pkgs.lib.optionalAttrs (
          builtins.elem system [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ]
        ) {
          # Official prebuilt CLI (static binary); no darwin-x86_64 upstream.
          boxd = pkgsUnfree.callPackage ./packages/boxd { };
          # Official prebuilt CLI/server; no darwin-x86_64; aarch64-linux is Neoverse/Graviton.
          lore = pkgs.callPackage ./packages/lore { };
          loreserver = pkgs.callPackage ./packages/loreserver { };
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
          # Official preview tarball is only fetched for x86_64-linux.
          zed-preview = pkgs.callPackage ./packages/zed-preview { };
          # Official prebuilt IRC client tarball; only x86_64-linux upstream.
          halloy = pkgs.callPackage ./packages/halloy { };
        }
        // pkgs.lib.optionalAttrs (pkgs.lib.hasSuffix "-linux" system) {
          # GNOME/GTK4 RSS reader; Linux only (WebKitGTK + libadwaita).
          pulp = pkgs.callPackage ./packages/pulp { };
          # GTK4/libadwaita default-app manager; Linux only.
          mimic = pkgs.callPackage ./packages/mimic { };
          # Minimalist GTK4/libadwaita file manager (mobile-friendly); Linux only.
          portfolio = pkgs.callPackage ./packages/portfolio { };
          # Chrome m148 Skia (Ladybird needs skia 148; nixpkgs ships 144).
          skia = pkgs.callPackage ./packages/skia { };
          # Qt6 web browser (LibWeb); Linux only.
          ladybird = pkgs.callPackage ./packages/ladybird {
            inherit (self.packages.${system}) skia;
          };
        }
        // pkgs.lib.optionalAttrs (system == "aarch64-darwin") {
          # Ladybird on macOS is marked broken upstream; exposed for parity with nixpkgs.
          ladybird = pkgs.callPackage ./packages/ladybird { };
        }
      );

      # Convenience: `nix run .#vit -- --help`, `nix run .#spinel -- --help`
      apps = forAllSystems (
        system:
        {
          vit = {
            type = "app";
            program = "${self.packages.${system}.vit}/bin/vit";
          };
          spinel = {
            type = "app";
            program = "${self.packages.${system}.spinel}/bin/spinel";
          };
          spin = {
            type = "app";
            program = "${self.packages.${system}.spinel}/bin/spin";
          };
          rook = {
            type = "app";
            program = "${self.packages.${system}.rook}/bin/rook";
          };
          whetuu = {
            type = "app";
            program = "${self.packages.${system}.whetuu}/bin/whetuu";
          };
          pullrun = {
            type = "app";
            program = "${self.packages.${system}.pullrun}/bin/pullrun";
          };
          gleam-preview = {
            type = "app";
            program = "${self.packages.${system}.gleam-preview}/bin/gleam-preview";
          };
          eyg = {
            type = "app";
            program = "${self.packages.${system}.eyg}/bin/eyg";
          };
          update = {
            type = "app";
            program = "${self.packages.${system}.update}/bin/update";
          };
          default = self.apps.${system}.vit;
        }
        // nixpkgs.lib.optionalAttrs (
          builtins.elem system [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ]
        ) {
          boxd = {
            type = "app";
            program = "${self.packages.${system}.boxd}/bin/boxd";
          };
          lore = {
            type = "app";
            program = "${self.packages.${system}.lore}/bin/lore";
          };
          loreserver = {
            type = "app";
            program = "${self.packages.${system}.loreserver}/bin/loreserver";
          };
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          zed-preview = {
            type = "app";
            program = "${self.packages.${system}.zed-preview}/bin/zed-preview";
          };
          halloy = {
            type = "app";
            program = "${self.packages.${system}.halloy}/bin/halloy";
          };
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system) {
          pulp = {
            type = "app";
            program = "${self.packages.${system}.pulp}/bin/pulp";
          };
          mimic = {
            type = "app";
            program = "${self.packages.${system}.mimic}/bin/mimic";
          };
          portfolio = {
            type = "app";
            program = "${self.packages.${system}.portfolio}/bin/portfolio";
          };
          ladybird = {
            type = "app";
            program = "${self.packages.${system}.ladybird}/bin/Ladybird";
          };
        }
        // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
          ladybird = {
            type = "app";
            program = "${self.packages.${system}.ladybird}/bin/Ladybird";
          };
        }
      );
    };
}
