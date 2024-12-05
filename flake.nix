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

    hostname = "rosetta-builder"; # FIXME: split into logical uses
    user = "builder"; # FIXME: split into darwin and linux

    sshKeyType = "ed25519";
    sshHostPrivateKeyFileName = "ssh_host_${sshKeyType}_key";
    sshHostPublicKeyFileName = "${sshHostPrivateKeyFileName}.pub";
    sshUserPrivateKeyFileName = "${user}_${sshKeyType}";
    sshUserPublicKeyFileName = "${sshUserPrivateKeyFileName}.pub";

    debug = true; # FIXME: disable

  in {
    packages."${linuxSystem}".default = nixos-generators.nixosGenerate (
    let
      imageFormat = "qcow-efi"; # must match `builderYaml.images.location`s extension
      pkgs = nixpkgs.legacyPackages."${linuxSystem}";

      sshdKeys = "sshd-keys";
      sshDirPath = "/etc/ssh";
      sshHostPrivateKeyFilePath = "${sshDirPath}/${sshHostPrivateKeyFileName}";

    in {
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

        networking.hostname = hostname;

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
              HostKey = sshHostPrivateKeyFilePath;
              PasswordAuthentication = false;
            };
          };
        };

        system = {
          disableInstallerTools = true;
          stateVersion = "24.05";
        };

        systemd.services."${sshdKeys}" =
        let
          sshdKeysVirtiofsTag = "mount0"; # suffix must match `builderYaml.mounts.location`s order
          sshdKeysDirPath = "/var/${sshdKeys}";
          sshAuthorizedKeysUserFilePath = "${sshDirPath}/authorized_keys.d/${user}";
          sshdService = "sshd.service";

        in {
          before = [ sshdService ];
          description = "Install sshd's host and authorized keys";
          enableStrictShellChecks = true;
          path = [ pkgs.mount pkgs.umount ];
          requiredBy = [ sshdService ];

          # must be idempotent in the face of partial failues
          script = ''
            mkdir -p '${sshdKeysDirPath}'
            mount \
              -t 'virtiofs' \
              -o 'nodev,noexec,nosuid,ro' \
              '${sshdKeysVirtiofsTag}' \
              '${sshdKeysDirPath}'

            mkdir -p "$(dirname '${sshHostPrivateKeyFilePath}')"
            (
              umask 'go-rwx'
              cp '${sshdKeysDirPath}/${sshHostPrivateKeyFileName}' '${sshHostPrivateKeyFilePath}'
            )

            mkdir -p "$(dirname '${sshAuthorizedKeysUserFilePath}')"
            cp '${sshdKeysDirPath}/${sshUserPublicKeyFileName}' '${sshAuthorizedKeysUserFilePath}'
            chmod 'a+r' '${sshAuthorizedKeysUserFilePath}'

            umount '${sshdKeysDirPath}'
            rmdir '${sshdKeysDirPath}'
          '';

          serviceConfig.Type = "oneshot";
          unitConfig.ConditionPathExists = "!${sshAuthorizedKeysUserFilePath}";
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
    });

    devShells."${darwinSystem}".default =
    let
      pkgs = nixpkgs.legacyPackages."${darwinSystem}";
    in pkgs.mkShell {
      packages = [ pkgs.lima ];
    };

    darwinModules.default = { lib, pkgs, ... }:
    let
      cores = 8;
      port = 2226;
      workingDirPath = "FIXME";

      linuxSshdKeysDirName = "linux-sshd-keys";

      builderYaml = (pkgs.formats.yaml {}).generate "${hostname}.yaml" {
        cpus = cores;

        images = [{
          # extension must match `imageFormat`
          location = "${self.packages."${linuxSystem}".default}/nixos.qcow2";
        }];

        memory = "6GiB";

        mounts = [{
          # order must match `sshdKeysVirtiofsTag`s suffix
          location = "${workingDirPath}/${linuxSshdKeysDirName}";
        }];

        rosetta.enabled = true;
        ssh.localPort = port;
      };

    in {
      environment.etc."ssh/ssh_config.d/100-${hostname}.conf".text = ''
        Host "${hostname}"
          GlobalKnownHostsFile "${workingDirPath}/ssh_known_hosts" # FIXME: variable
          Hostname localhost
          HostKeyAlias "${hostname}"
          Port "${port}"
          User "${user}"
          IdentityFile "${workingDirPath}/${sshUserPrivateKeyFileName}"
      '';

      users.users."${user}" = { # FIXME: separate darwinUser?
        # createHome = true;
        # gid = FIXME;
        # home = workingDirPath;
        isHidden = true;
        # uid = FIXME;
      };

      launchd.daemons."${hostname}" = {
        environment.LIMA_HOME = "lima";
        path = []; # FIXME: fill pkgs.grep? pkgs.lima pkgs.openssh

        script = ''
          # FIXME: variables
          # must be idempotent in the face of partial failues
          limactl list -q 2>'/dev/null' | grep -q '${hostname}' || {
            ssh-keygen \
              -C '${user}@darwin' -f '${sshUserPrivateKeyFileName}' -N "" -t '${sshKeyType}'
            ssh-keygen \
              -C 'root@${hostname}' -f '${sshHostPrivateKeyFileName}' -N "" -t '${sshKeyType}'

            mkdir -p '${linuxSshdKeysDirName}'
            mv \
              '${sshUserPublicKeyFileName}' \
              '${sshHostPrivateKeyFileName}' \
              '${linuxSshdKeysDirName}'

            echo "${hostname} $(cat '${sshHostPublicKeyFileName}')" >'ssh_known_hosts'

            limactl create '${builderYaml}'
          }

          exec limactl start --foreground '${hostname}'
        '';

        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          UserName = user;
          WorkingDirectory = workingDirPath;
        } // lib.optionalAttrs debug {
          StandardErrorPath = "/tmp/${hostname}.err.log";
          StandardOutPath = "/tmp/${hostname}.out.log";
        };
      };

      nix = {
        buildMachines = [{
          hostName = hostname;
          maxJobs = cores;
          protocol = "ssh-ng";
          supportedFeatures = [ "benchmark" "big-parallel" "kvm" ];
          systems = [ linuxSystem "x86_64-linux" ];
        }];

        distributedBuilds = true;
        settings.builders-use-substitutes = true;
      };

    };
  };
}
