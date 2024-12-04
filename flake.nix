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
    lib = nixpkgs.lib;

    debug = true; # FIXME: disable
    keysDirectory = "/var/keys";
    keyType = "ed25519";
    user = "builder";

  in {
    packages."${linuxSystem}".default = nixos-generators.nixosGenerate {
      format = "qcow-efi";

      modules = [ {
        imports = [ (nixpkgs + "/nixos/modules/profiles/qemu-guest.nix") ];

        boot = {
          kernelParams = [ "console=tty0" ];

          loader = {
            efi.canTouchEfiVariables = true;
            systemd-boot.enable = true; 
          };
        };

        documentation.enable = false;

        fileSystems = {
          "/".options = [ "discard" "noatime" ];
          "/boot".options = [ "discard" "noatime" "umask=0077" ];

          "${keysDirectory}" = {
            device = "mount0"; # must match `mounts` order in builder.yaml
            fsType = "virtiofs";
            options = [ "nodev" "noexec" "nosuid" "ro" ];
          };
        };

        nix = {
          channel.enable = false;
          registry.nixpkgs.flake = nixpkgs;

          settings = {
            auto-optimise-store = true;
            experimental-features = [ "flakes" "nix-command" ];
            min-free = "5G";
            max-free = "7G";
          };
        };

        security = {
          polkit = lib.optionalAttrs debug {
            enable = true;
            extraConfig = ''
              polkit.addRule(function(action, subject) {
                if (action.id === "org.freedesktop.login1.power-off" && subject.user === "${user}") {
                  return "yes";
                } else {
                  return "no";
                }
              })
            '';
          };

          sudo = {
            enable = debug;
            wheelNeedsPassword = !debug;
          };
        };

        services = {
          getty = lib.optionalAttrs debug { autologinUser = user; };

          openssh = {
            authorizedKeysFiles = [ "${keysDirectory}/%u_${keyType}.pub" ];
            enable = true;
            hostKeys = []; # disable automatic host key generation

            settings = {
              HostKey = "${keysDirectory}/ssh_host_${keyType}_key";
              PasswordAuthentication = false;
            };
          };
        };

        system = {
          disableInstallerTools = true;
          stateVersion = "24.05";
        };

        users.users."${user}" = {
          isNormalUser = true;
          extraGroups = lib.optionals debug [ "wheel" ];
        };

        virtualisation.rosetta = {
          enable = true;
          mountTag = "vz-rosetta";
        };
      } ];

      system = linuxSystem;
    };

    devShells."${system}".default = pkgs.mkShell { packages = [
      pkgs.lima
    ]; };
  };
}
