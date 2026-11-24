{config, ...}: {
  # Declarative Remote Login, mirroring the key-only pattern every other
  # home-lab box already uses (hosts/nixos/_homelab/base.nix). Trusting the
  # same shared pubkey here is what lets T2/T3/L2 (which already hold the
  # private half via common/home/age.nix's agenix identity) SSH into L1.
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
    '';
  };

  users.users.${config.hostSpec.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiaeSJP9C/rfe4nldhwrXjCJ3qP4qTWreR4lHMr/1BI"
  ];
}
