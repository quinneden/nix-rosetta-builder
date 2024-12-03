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

        # boot.loader = { # FIXME: use
        #   systemd-boot.enable = true; 
        #   efi.canTouchEfiVariables = true;
        # };
        boot.initrd.availableKernelModules = [ "xhci_pci" ];
        boot.initrd.kernelModules = [ ];
        boot.kernelModules = [ ];
        boot.kernelParams = [ "console=tty0" ];
        boot.extraModulePackages = [ ];
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        swapDevices = [ ];

        networking.useDHCP = nixpkgs.lib.mkDefault true;

        nixpkgs.hostPlatform = nixpkgs.lib.mkDefault "aarch64-linux";

        # services.openssh = { # FIXME: use
        #   enable = true;
        #   settings.PermitRootLogin = "yes";
        # };
        services.openssh.enable = true;
        services.openssh.settings.PermitRootLogin = "yes"; # FIXME: remove

        system.stateVersion = "24.05"; # Did you read the comment?

        virtualisation.rosetta = {
          enable = true;
          mountTag = "vz-rosetta";
        };

        users.users.root.password = "nixos"; # FIXME:

        # fileSystems."/boot" = {
        #   device = "/dev/disk/by-label/ESP"; # /dev/vda1
        #   fsType = "vfat";
        # };

        # fileSystems."/" = {
        #   device = "/dev/disk/by-label/nixos";
        #   autoResize = true;
        #   fsType = "ext4";
        #   options = ["noatime" "nodiratime" "discard"];
        # };
      } ];
      system = linuxSystem;
    };

    devShells."${system}".default = pkgs.mkShell { packages = [
      pkgs.lima
      pkgs.sshpass
    ]; };
  };
}
