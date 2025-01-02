{
  description = "Lima-based, Rosetta 2-enabled, Apple silicon (macOS/Darwin)-hosted Linux builder";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixos-generators, nixpkgs }:
  let
    darwinSystem = "aarch64-darwin";
    linuxSystem = builtins.replaceStrings [ "darwin" ] [ "linux" ] darwinSystem;
    lib = nixpkgs.lib;

  in {
    packages."${linuxSystem}".default =
      nixpkgs.legacyPackages."${linuxSystem}".callPackage ./package.nix {
        inherit linuxSystem nixos-generators nixpkgs;
      };

    devShells."${darwinSystem}".default =
    let
      pkgs = nixpkgs.legacyPackages."${darwinSystem}";
    in pkgs.mkShell {
      packages = [ pkgs.lima ];
    };

    darwinModules.default = import ./module.nix {
      package = self.packages."${linuxSystem}".default;
      inherit linuxSystem;
    };
  };
}
