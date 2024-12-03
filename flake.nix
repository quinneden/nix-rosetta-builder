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
    system = "aarch64-darwin";
    pkgs = nixpkgs.legacyPackages."${system}";
    linuxSystem = builtins.replaceStrings [ "darwin" ] [ "linux" ] system;

  in {
    packages."${linuxSystem}".default = nixos-generators.nixosGenerate {
      format = "qcow-efi";
      modules = [ {
        # imports = [ # FIXME: include?
        #   (nixpkgs + "/nixos/modules/profiles/qemu-guest.nix")
        # ];

        # FIXME: use?
        # nix.registry.nixpkgs.flake = nixpkgs;
        # virtualisation.diskSize = 10 * 1024;

        boot = {
          kernelParams = [ "console=tty0" ];

          loader = {
            efi.canTouchEfiVariables = true;
            systemd-boot.enable = true; 
          };
        };

        fileSystems = {
          "/".options = [ "discard" "noatime" ];
          "/boot".options = [ "dmask=0077" "fmask=0077" "noatime" ];
        };

        networking.useDHCP = nixpkgs.lib.mkDefault true;

        nixpkgs.hostPlatform = nixpkgs.lib.mkDefault "aarch64-linux";

        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "yes"; # FIXME: remove
        };

        swapDevices = [ ];

        system.stateVersion = "24.05"; # Did you read the comment?

        users.users.root.password = "nixos"; # FIXME:

        virtualisation.rosetta = {
          enable = true;
          mountTag = "vz-rosetta";
        };
      } ];
      system = linuxSystem;
    };

    devShells."${system}".default = pkgs.mkShell { packages = [
      pkgs.lima
      pkgs.sshpass
    ]; };
  };
}
