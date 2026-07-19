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
          default = self.packages.${system}.vit;
        }
      );

      # Convenience: `nix run .#vit -- --help`
      apps = forAllSystems (system: {
        vit = {
          type = "app";
          program = "${self.packages.${system}.vit}/bin/vit";
        };
        default = self.apps.${system}.vit;
      });
    };
}
