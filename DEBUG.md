# Debugging nix-rosetta-builder

Rough debugging notes and suggestions.
If you think of something that's missing or have something to add please
[open an issue](https://github.com/cpick/nix-rosetta-builder/issues/new).

## Gather information

### General

Test whether VM is running:
```sh
sudo ssh rosetta-builder
```

### Launchd

See the VM daemon's status in `launchd`:
```sh
launchctl print system/org.nixos.rosetta-builderd
```
Some fields in that output that deserve attention (see also "launchd.log" below):
* state
* pid
* sockets."Listener".error

Unload/stop the VM daemon:
```sh
sudo launchctl bootout system/org.nixos.rosetta-builderd
```
(Possibly followed by `sudo rm /Library/LaunchDaemons/org.nixos.rosetta-builderd.plist` to force a
subsequent `darwin-rebuild` to reload it, or else...)

(Re)load the VM daemon:
```sh
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.rosetta-builderd.plist
```

## Logs

* /private/var/log/com.apple.xpc.launchd/launchd.log
* /var/lib/rosetta-builder/.lima/rosetta-builder-vm/ha.stderr.log
* /var/lib/rosetta-builder/.lima/rosetta-builder-vm/ha.stdout.log

When module.nix's `debugInsecurely = true`:
* /tmp/rosetta-builderd.err.log
* /tmp/rosetta-builderd.out.log

## Uninstall

See [README.md#Uninstall].
