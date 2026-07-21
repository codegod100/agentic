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
        in
        {
          vit = pkgs.callPackage ./packages/vit { };
          spinel = pkgs.callPackage ./packages/spinel { };
          rook = pkgs.callPackage ./packages/rook { };
          default = self.packages.${system}.vit;
        }
      );

      # Convenience: `nix run .#vit -- --help`, `nix run .#spinel -- --help`
      apps = forAllSystems (system: {
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
        default = self.apps.${system}.vit;
      });
    };
}
