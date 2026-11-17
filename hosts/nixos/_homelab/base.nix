# Shared by every home-lab box (T1, T2, T3, MON1). Imported explicitly from
# hosts/nixos/enum.nix; the leading underscore keeps import-tree from pulling
# this directory into any single host on its own.
{
  config,
  lib,
  hostPlatform,
  ...
}: let
  # Same single identity the VPS hosts authorize (== agenix recipient pubkey).
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiaeSJP9C/rfe4nldhwrXjCJ3qP4qTWreR4lHMr/1BI";
in {
  # mkCfg passes a prebuilt `pkgs`, leaving nixpkgs.hostPlatform unset, and the
  # facter module reads it. Option-default priority so a real facter.json
  # (which sets it from the report) still wins.
  nixpkgs.hostPlatform = lib.mkOptionDefault hostPlatform.system;

  # Each host keeps its own report next to its config. It starts as `{}`,
  # which leaves hardware.facter.enable off until the real report is copied
  # in (see hosts/README.md, "Home-lab bootstrap").
  hardware.facter.reportPath = lib.mkDefault (../. + "/${config.hostSpec.hostName}/facter.json");

  # Headless and key-only; root key login is what nixos-anywhere and
  # deploy-rs use.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [sshPubKey];
  users.users."${config.hostSpec.username}" = {
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [sshPubKey];
  };

  # Scraped by MON1 (hosts/nixos/MON1/monitoring.nix).
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = ["systemd"];
  };
}
