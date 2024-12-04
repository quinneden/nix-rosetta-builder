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
    linuxPkgs = nixpkgs.legacyPackages."${linuxSystem}";
    lib = nixpkgs.lib;

    user = "builder";

    sshdkeysVirtiofsTag = "mount0"; # must match `mounts` order in builder.yaml
    sshdkeysDirectory = "/var/sshdkeys";
    sshDirectory = "/etc/ssh";
    sshKeyType = "ed25519";
    sshHostKeyFilename = "ssh_host_${sshKeyType}_key";
    sshHostKeyPath = "${sshDirectory}/${sshHostKeyFilename}";
    sshAuthorizedKeysUserPath = "${sshDirectory}/authorized_keys.d/${user}";
    sshdService = "sshd.service";

    debug = true; # FIXME: disable

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
                if (
                  (
                    action.id === "org.freedesktop.login1.power-off"
                    || action.id === "org.freedesktop.login1.reboot"
                  )
                  && subject.user === "${user}"
                ) {
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
            enable = true;
            hostKeys = []; # disable automatic host key generation

            settings = {
              HostKey = sshHostKeyPath;
              PasswordAuthentication = false;
            };
          };
        };

        system = {
          disableInstallerTools = true;
          stateVersion = "24.05";
        };

        systemd.services.sshdkeys = {
          before = [ sshdService ];
          description = "Install sshd's host and authorized keys";
          requiredBy = [ sshdService ];

          script = ''
            export PATH="${lib.makeBinPath [ linuxPkgs.mount linuxPkgs.umount ]}:$PATH"

            umask 'go-w'

            mkdir -p '${sshdkeysDirectory}'
            mount \
              -t 'virtiofs' \
              -o 'nodev,noexec,nosuid,ro' \
              '${sshdkeysVirtiofsTag}' \
              '${sshdkeysDirectory}'

            mkdir -p "$(dirname '${sshHostKeyPath}')"
            (umask 'go-rwx' ; cp '${sshdkeysDirectory}/${sshHostKeyFilename}' '${sshHostKeyPath}')

            mkdir -p "$(dirname '${sshAuthorizedKeysUserPath}')"
            cp '${sshdkeysDirectory}/${user}_${sshKeyType}.pub' '${sshAuthorizedKeysUserPath}'
            chmod 'a+r' '${sshAuthorizedKeysUserPath}'

            umount '${sshdkeysDirectory}'
            rmdir '${sshdkeysDirectory}'
          '';

          serviceConfig.Type = "oneshot";
          unitConfig.ConditionPathExists = "!${sshAuthorizedKeysUserPath}";
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
