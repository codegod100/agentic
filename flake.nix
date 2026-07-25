{
  description = "Nix packages for third-party projects that don't ship their own flakes";

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
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
          # Official preview tarball is only fetched for x86_64-linux.
          zed-preview = pkgs.callPackage ./packages/zed-preview { };
        }
        // pkgs.lib.optionalAttrs (pkgs.lib.hasSuffix "-linux" system) {
          # GNOME/GTK4 RSS reader; Linux only (WebKitGTK + libadwaita).
          pulp = pkgs.callPackage ./packages/pulp { };
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
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          zed-preview = {
            type = "app";
            program = "${self.packages.${system}.zed-preview}/bin/zed-preview";
          };
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system) {
          pulp = {
            type = "app";
            program = "${self.packages.${system}.pulp}/bin/pulp";
          };
        }
      );
    };
}
