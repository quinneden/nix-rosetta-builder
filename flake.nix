{
  description = "Lima-based, Rosetta 2-enabled, macOS (Darwin) builder";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages."${system}";

    in {
      devShells."${system}".default = pkgs.mkShell { packages = [
        pkgs.lima
      ]; };
    };
}
