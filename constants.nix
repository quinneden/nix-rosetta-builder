rec {
  name = "rosetta-builder"; # update `darwinGroup` if adding or removing special characters
  linuxHostName = name; # no prefix because it's user visible (on prompt when `ssh`d in)
  linuxUser = "builder"; # follow linux-builder/darwin-builder precedent

  sshKeyType = "ed25519";
  sshHostPrivateKeyFileName = "ssh_host_${sshKeyType}_key";
  sshHostPublicKeyFileName = "${sshHostPrivateKeyFileName}.pub";
  sshUserPrivateKeyFileName = "ssh_user_${sshKeyType}_key";
  sshUserPublicKeyFileName = "${sshUserPrivateKeyFileName}.pub";

  # debug = false; # enable root access in VM and debug logging
}
