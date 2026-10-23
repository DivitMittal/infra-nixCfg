{
  config,
  modulesPath,
  pkgs,
  ...
}: let
  # Same single identity the VPS hosts authorize (== agenix recipient pubkey).
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiaeSJP9C/rfe4nldhwrXjCJ3qP4qTWreR4lHMr/1BI";
in {
  imports = [
    (modulesPath + "/installer/netboot/netboot.nix")
  ];

  # Deliberately not importing common/hosts/nixos here (unlike the iso class):
  # a netboot ramdisk is fetched over PXE/TFTP into RAM on every boot, so it
  # must stay small — no desktop/GUI stack, just enough to run nixos-facter
  # and hand off to an install. common/hosts/all/users.nix creates the
  # hostSpec user but expects common/hosts/nixos/misc.nix to mark it a normal
  # user, which isn't imported here, so do that directly.
  users.users."${config.hostSpec.username}" = {
    isNormalUser = true;
    group = config.hostSpec.username;
  };
  users.groups."${config.hostSpec.username}" = {};

  system.stateVersion = "26.11";

  # fwupd here lets you check/apply UEFI firmware updates from the PXE shell
  # before (or without) installing NixOS to local disk — see hosts/README.md.
  # EspLocation isn't set: netboot has no fstab/persistent mounts, so there's
  # nothing at /boot for fwupd to auto-detect yet. Mount the target disk's ESP
  # at /boot manually first (matches T1's installed-system convention, so no
  # EspLocation override is needed once it's mounted there).
  services.fwupd.enable = true;

  environment.systemPackages = [pkgs.nixos-facter];

  # nixos-anywhere (via bootstrap-remote) drives the install over SSH as root,
  # so the ramdisk must come up with sshd and the key already authorized.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [sshPubKey];

  # Console access for the PXE-booted report/rescue environment.
  users.users.root.initialPassword = "nixos";
}
