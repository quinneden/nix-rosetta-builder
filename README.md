# lima-builder

Lima-based, Rosetta 2-enabled, Apple silicon (macOS/Darwin)-hosted Linux builder.

## Usage

Build image:
```sh
nix build '.#packages.aarch64-linux.default'
```

Create and start VM (optionally add `--video` for console):
```sh
limactl start --tty=false --foreground builder.yaml
```
Periodic informational messages like the following are expected:
> Waiting for the essential requirement 1 of 2: "ssh" ...

SSH:
```sh
ssh -p 2226 -i ~/lima-builder-keys/builder_ed25519 builder@localhost
```

Delete VM:
```sh
limactl delete -f builder
```
