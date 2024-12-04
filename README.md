# rosetta-builder

Lima-based, Rosetta 2-enabled, Apple silicon (macOS/Darwin)-hosted Linux builder.

## Setup

Build image:
```sh
nix build '.#packages.aarch64-linux.default'
```

```sh
mkdir -p ~/rosetta-builder/ssh{,d}keys
ssh-keygen -C 'builder@localhost' -f ~/rosetta-builder/builder_ed25519 -N '' -t ed25519
ssh-keygen -C 'root@rosetta-builer' -f ~/rosetta-builder/ssh_host_ed25519_key -N '' -t ed25519
mv ~/rosetta-builder/builder_ed25519 ~/rosetta-builder/ssh_host_ed25519_key.pub ~/rosetta-builder/sshkeys/
mv ~/rosetta-builder/builder_ed25519.pub ~/rosetta-builder/ssh_host_ed25519_key ~/rosetta-builder/sshdkeys/
```

## Usage

Create and start VM (optionally add `--video` for console):
```sh
limactl start --tty=false --foreground builder.yaml
```
Periodic informational messages like the following are expected:
> Waiting for the essential requirement 1 of 2: "ssh" ...

SSH:
```sh
ssh -p 2226 -i ~/rosetta-builder/sshkeys/builder_ed25519 builder@localhost
```

Delete VM:
```sh
limactl delete -f builder
```
