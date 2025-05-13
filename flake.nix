{
  description = "Lima-based, Rosetta 2-enabled, Apple silicon (macOS/Darwin)-hosted Linux builder";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      lix-module,
      self,
    }:
    let
      darwinSystem = "aarch64-darwin";
      linuxSystem = builtins.replaceStrings [ "darwin" ] [ "linux" ] darwinSystem;
    in
    {
      packages."${linuxSystem}" =
        let
          pkgs = nixpkgs.legacyPackages."${linuxSystem}";
        in
        rec {
          default = image;

          image = pkgs.callPackage ./package.nix {
            inherit
              linuxSystem
              lix-module
              nixpkgs
              ;
            # Optional: override default argument values passed to the derivation.
            # Many can also be accessed through the module.
          };
        };

      devShells."${darwinSystem}".default =
        let
          pkgs = nixpkgs.legacyPackages."${darwinSystem}";
        in
        pkgs.mkShell {
          packages = [ pkgs.lima ];
        };

      darwinModules.default = import ./module.nix {
        inherit linuxSystem;
        image = self.packages."${linuxSystem}".image;
      };

      formatter."${darwinSystem}" = nixpkgs.legacyPackages."${darwinSystem}".nixfmt-rfc-style;
    };
}
