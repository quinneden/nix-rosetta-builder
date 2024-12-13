# rosetta-builder

A Rosetta 2-enabled, Apple silicon (macOS/Darwin)-hosted Linux Nix builder.

Runs on aarch64-darwin and builds aarch64-linux (natively) and x86_64-linux (using Rosetta 2).

## nix-darwin flake setup

flake.nix:
```nix
{
  description = "Configure macOS using nix-darwin with rosetta-builder";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nix-rosetta-builder, nixpkgs }: {
    darwinConfigurations."${hostname}" = nix-darwin.lib.darwinSystem {
      modules = [ nix-rosetta-builder.darwinModules.default ];
    };
  };
}
```

# Uninstall

Remove `nix-rosetta-builder` from nix-darwin's flake.nix, `darwin-rebuild`, and then:
```sh
sudo rm -r /var/lib/rosetta-builder
```
