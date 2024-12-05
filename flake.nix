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

    cores = 8;
    hostname = "rosetta-builder";
    imageFormat = "qcow-efi"; # must match `builderYaml.images.location`s extension
    port = 2226;
    user = "builder";

    sshdkeysVirtiofsTag = "mount0"; # suffix must match `builderYaml.mounts.location`s order
    guestSshdkeysDirectory = "/var/sshdkeys";
    sshDirectory = "/etc/ssh";
    sshKeyType = "ed25519";
    sshHostKeyFilename = "ssh_host_${sshKeyType}_key";
    sshHostKeyPath = "${sshDirectory}/${sshHostKeyFilename}";
    sshAuthorizedKeysUserPath = "${sshDirectory}/authorized_keys.d/${user}";
    sshdService = "sshd.service";

    debug = true; # FIXME: disable

  in {
    packages."${linuxSystem}".default = nixos-generators.nixosGenerate {
      format = imageFormat;

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

          # must be idempotent in the face of partial failues
          script = ''
            PATH="${lib.makeBinPath [ linuxPkgs.mount linuxPkgs.umount ]}:$PATH"
            export PATH

            mkdir -p '${guestSshdkeysDirectory}'
            mount \
              -t 'virtiofs' \
              -o 'nodev,noexec,nosuid,ro' \
              '${sshdkeysVirtiofsTag}' \
              '${guestSshdkeysDirectory}'

            mkdir -p "$(dirname '${sshHostKeyPath}')"
            (
              umask 'go-rwx'
              cp '${guestSshdkeysDirectory}/${sshHostKeyFilename}' '${sshHostKeyPath}'
            )

            mkdir -p "$(dirname '${sshAuthorizedKeysUserPath}')"
            cp \
              '${guestSshdkeysDirectory}/${user}_${sshKeyType}.pub' \
              '${sshAuthorizedKeysUserPath}'
            chmod 'a+r' '${sshAuthorizedKeysUserPath}'

            umount '${guestSshdkeysDirectory}'
            rmdir '${guestSshdkeysDirectory}'
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

    darwinModules.default = { lib, ... }:
    let
      workingDirectory = "FIXME";

      builderYaml = (pkgs.formats.yaml {}).generate "${hostname}.yaml" {
        cpus = cores;

        images = [{
          # extension must match `imageFormat`
          location = "${self.packages."${linuxSystem}".default}/nixos.qcow2";
        }];

        memory = "6GiB";

        mounts = [{
          # order must match `sshdkeysVirtiofsTag`s suffix 
          location = "${workingDirectory}/sshdkeys"; # FIXME: variable
        }];

        rosetta.enabled = true;
        ssh.localPort = port;
      };

    in {
      environment.etc."ssh/ssh_config.d/100-${hostname}.conf".text = ''
        Host "${hostname}"
          GlobalKnownHostsFile "${workingDirectory}/ssh_known_hosts" # FIXME: variable
          Hostname localhost
          HostKeyAlias "${hostname}"
          Port "${port}"
          User "${user}"
          IdentityFile "${workingDirectory}/${user}_${sshKeyType}" # FIXME: variable
      '';

      users.users."${user}" = { # FIXME: separate hostUser?
        # createHome = true;
        # gid = FIXME;
        # home = workingDirectory;
        isHidden = true;
        # uid = FIXME;
      };

      launchd.daemons."${hostname}" = {
        script = ''
          PATH="${lib.makeBinPath []}:$PATH" # FIXME: fill pkgs.grep? pkgs.lima pkgs.openssh
          export PATH

          LIMA_HOME='lima'
          export LIMA_HOME

          # FIXME: variables
          # must be idempotent in the face of partial failues
          limactl list -q 2>'/dev/null' | grep -q '${hostname}' || {
            mkdir -p 'sshdkeys'

            ssh-keygen -C '${user}@localhost' -f '${user}_${sshKeyType}' -N "" -t '${sshKeyType}'
            ssh-keygen \
              -C 'root@${hostname}' -f 'ssh_host_${sshKeyType}_key' -N "" -t '${sshKeyType}'

            mv '${user}_${sshKeyType}.pub' 'ssh_host_${sshKeyType}_key' 'sshdkeys'
            echo "${hostname} $(cat 'ssh_host_${sshKeyType}_key.pub')" >'ssh_known_hosts'

            limactl create '${builderYaml}'
          }

          exec limactl start --foreground '${hostname}'
        '';

        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          UserName = user;
          WorkingDirectory = workingDirectory;
        };
      };

      nix = {
        buildMachines = [{
          hostName = hostname;
          maxJobs = cores;
          protocol = "ssh-ng";
          sshUser = user; # FIXME: separate hostUser from guestUser
          sshKey = "${workingDirectory}/${user}_${sshKeyType}"; # FIXME: variables
          supportedFeatures = [ "benchmark" "big-parallel" "kvm" ];
          systems = [ linuxSystem "x86_64-linux" ];
        }];

        distributedBuilds = true;
        settings.builders-use-substitutes = true;
      };

    };
  };
}
