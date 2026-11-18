# Shared by every home-lab box (T1, T2, T3, MON1). Imported explicitly from
# hosts/nixos/enum.nix; the leading underscore keeps import-tree from pulling
# this directory into any single host on its own.
{
  config,
  lib,
  inputs,
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

  # Reports live in the private infra-nixCfg-secrets (`homelab.facter`): they
  # carry component serials and MACs. Hosts without one yet get a `{}`
  # placeholder, which leaves hardware.facter.enable off.
  hardware.facter.reportPath = lib.mkDefault (
    inputs.infra-nixCfg-secrets.homelab.facter.${config.hostSpec.hostName} or ./facter-placeholder.json
  );

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
  # Console login at a keyboard and screen uses the same passwords as the
  # VPSes (yescrypt hashes, decrypted by agenix at activation). SSH stays
  # key-only above. The identity is seeded at install time by bootstrap.
  imports = [inputs.agenix.nixosModules.default];
  age.identityPaths = ["/var/lib/agenix/id_ed25519"];
  age.secrets."users/div".file = inputs.infra-nixCfg-secrets + "/secrets/users/div.age";
  age.secrets."users/root".file = inputs.infra-nixCfg-secrets + "/secrets/users/root.age";

  # These hosts are provisioned with locked accounts. With mutableUsers=true,
  # NixOS preserves their existing shadow entries even after password files
  # become available; enforce the decrypted hashes on every activation.
  users.mutableUsers = false;

  users.users.root = {
    openssh.authorizedKeys.keys = [sshPubKey];
    hashedPasswordFile = config.age.secrets."users/root".path;
  };
  users.users."${config.hostSpec.username}" = {
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [sshPubKey];
    hashedPasswordFile = config.age.secrets."users/div".path;
  };

  # The public resolver defaults cannot answer the router's local .lan names
  # used by monitoring and the k3s worker's server-discovery address.
  networking.nameservers = ["192.168.2.1"];

  # Scraped by MON1 (hosts/nixos/MON1/monitoring.nix).
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = ["systemd"];
  };
}
