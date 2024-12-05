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

    name = "rosetta-builder"; # update `darwinGroup` if adding or removing special characters
    linuxHostname = name; # no prefix because it's user visible (on prompt when `ssh`d in)
    linuxUser = "builder"; # follow linux-builder/darwin-builder precedent

    sshKeyType = "ed25519";
    sshHostPrivateKeyFileName = "ssh_host_${sshKeyType}_key";
    sshHostPublicKeyFileName = "${sshHostPrivateKeyFileName}.pub";
    sshUserPrivateKeyFileName = "$ssh_user_${sshKeyType}";
    sshUserPublicKeyFileName = "${sshUserPrivateKeyFileName}.pub";

    debug = true; # FIXME: disable

  in {
    packages."${linuxSystem}".default = nixos-generators.nixosGenerate (
    let
      imageFormat = "qcow-efi"; # must match `vmYaml.images.location`s extension
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

        networking.hostname = linuxHostname;

        nix = {
          channel.enable = false;
          registry.nixpkgs.flake = nixpkgs;

          settings = {
            auto-optimise-store = true;
            experimental-features = [ "flakes" "nix-command" ];
            min-free = "5G";
            max-free = "7G";
            trusted-users = [ linuxUser ];
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
                  && subject.user === "${linuxUser}"
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
          getty = lib.optionalAttrs debug { autologinUser = linuxUser; };

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
          sshdKeysVirtiofsTag = "mount0"; # suffix must match `vmYaml.mounts.location`s order
          sshdKeysDirPath = "/var/${sshdKeys}";
          sshAuthorizedKeysUserFilePath = "${sshDirPath}/authorized_keys.d/${linuxUser}";
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

        users.users."${linuxUser}" = {
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
      daemonName = "${name}d";
      darwinGroup = builtins.replaceStrings [ "-" ] [ "" ] name; # keep in sync with `name`s format
      darwinUser = "_${darwinGroup}";
      linuxSshdKeysDirName = "linux-sshd-keys";
      port = 2226;
      sshGlobalKnownHostsFileName = "ssh_known_hosts";
      sshHost = name; # no prefix because it's user visible (in `sudo ssh '${sshHost}'`)
      sshHostKeyAlias = "${sshHost}-key";
      workingDirPath = "/var/lib/${name}";

      vmYaml = (pkgs.formats.yaml {}).generate "${name}.yaml" {
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
      environment.etc."ssh/ssh_config.d/100-${sshHost}.conf".text = ''
        Host "${sshHost}"
          GlobalKnownHostsFile "${workingDirPath}/${sshGlobalKnownHostsFileName}"
          Hostname localhost
          HostKeyAlias "${sshHostKeyAlias}"
          Port "${port}"
          User "${linuxUser}"
          IdentityFile "${workingDirPath}/${sshUserPrivateKeyFileName}"
      '';

      users = {
        # FIXME: use?
        # groups."${darwinGroup}" = {
        #   # gid = darwinGid; # FIXME
        # };

        # knownGroups = [ darwinGroup ]; # FIXME: use?
        # knownUsers = [ darwinUser ]; # FIXME: use?

        users."${darwinUser}" = {
          # createHome = true; # FIXME: use?
          # gid = darwinGid; # FIXME: use?
          # home = workingDirPath; # FIXME: use?
          isHidden = true;
          # uid = FIXME; # FIXME: use?
        };
      };

      launchd.daemons."${daemonName}" = {
        environment.LIMA_HOME = "lima";
        path = []; # FIXME: fill pkgs.grep? pkgs.lima pkgs.openssh

        script =
        let
          vmName = "${name}-vm";

        in ''
          # must be idempotent in the face of partial failues
          limactl list -q 2>'/dev/null' | grep -q '${vmName}' || {
            ssh-keygen \
              -C '${darwinUser}@darwin' -f '${sshUserPrivateKeyFileName}' -N "" -t '${sshKeyType}'
            ssh-keygen \
              -C 'root@${linuxHostname}' -f '${sshHostPrivateKeyFileName}' -N "" -t '${sshKeyType}'

            mkdir -p '${linuxSshdKeysDirName}'
            mv \
              '${sshUserPublicKeyFileName}' '${sshHostPrivateKeyFileName}' '${linuxSshdKeysDirName}'

            echo "${sshHostKeyAlias} $(cat '${sshHostPublicKeyFileName}')" \
            >'${sshGlobalKnownHostsFileName}'

            limactl create --name='${vmName}' '${vmYaml}'
          }

          exec limactl start --foreground '${vmName}'
        '';

        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          UserName = darwinUser;
          WorkingDirectory = workingDirPath;
        } // lib.optionalAttrs debug {
          StandardErrorPath = "/tmp/${daemonName}.err.log";
          StandardOutPath = "/tmp/${daemonName}.out.log";
        };
      };

      nix = {
        buildMachines = [{
          hostName = sshHost;
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
