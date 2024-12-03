# lima-builder

Lima-based, Rosetta 2-enabled, Apple silicon (macOS/Darwin)-hosted Linux builder.

## Usage

Build image:
```sh
nix build '.#packages.aarch64-linux.default'
cp result/nixos.img .
chmod +w nixos.img
```

Create and start VM (optionally add `--video` for console):
```sh
limactl start --tty=false --foreground nixos.yaml
```

SSH:
```sh
sshpass -p nixos ssh -p 2226 -o NoHostAuthenticationForLocalhost=yes root@localhost
```

Delete VM:
```sh
limactl delete -f nixos
```
