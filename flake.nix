{
  description = "Lima-based, Rosetta 2-enabled, Apple silicon (macOS/Darwin)-hosted Linux builder";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixos-generators,
    nixpkgs,
  }: let
    darwinSystem = "aarch64-darwin";
    linuxSystem = builtins.replaceStrings ["darwin"] ["linux"] darwinSystem;
  in {
    packages."${linuxSystem}" = let
      pkgs = nixpkgs.legacyPackages."${linuxSystem}";
    in rec {
      default = image;

      image = pkgs.callPackage ./package.nix {
        inherit linuxSystem nixos-generators nixpkgs;
        # Optional: override default argument values passed to the derivation.
        # These can also be accessed through the module.
        #   debug = false;
        #   onDemand = false;
        #   enableRosetta = true;
        #   extraConfig = { };
      };
    };

    devShells."${darwinSystem}".default = let
      pkgs = nixpkgs.legacyPackages."${darwinSystem}";
    in
      pkgs.mkShell {
        packages = [pkgs.lima];
      };

    darwinModules.default = import ./module.nix {
      inherit linuxSystem;
      image = self.packages."${linuxSystem}".image;
    };
  };
}
