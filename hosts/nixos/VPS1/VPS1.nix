{
  config,
  lib,
  inputs,
  ...
}: let
  secretsPath = inputs.infra-nixCfg-secrets + "/secrets";
  # Single authorized identity (== the agenix recipient pubkey in infra-nixCfg-secrets/secrets/secrets.nix).
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiaeSJP9C/rfe4nldhwrXjCJ3qP4qTWreR4lHMr/1BI";
in {
  # --- Boot: Mumbai KVM VPS is legacy BIOS; disko.nix's EF02 partition registers /dev/sda with GRUB ---
  boot.loader.grub.enable = true;

  # virtio drivers for KVM disk/net/balloon + generic SATA/USB storage modules
  boot.initrd.availableKernelModules = ["ahci" "sd_mod" "sr_mod" "xhci_pci" "uhci_hcd" "ehci_pci" "ata_piix"];
  boot.initrd.kernelModules = ["virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net" "virtio_balloon"];

  # --- Networking: VPS1 uses a static private IP, NAT'd to the public IP ---
  # Mumbai KVM VPS for interactive workloads (~30ms RTT): 10.10.10.51/24 via 10.10.10.1, MAC bc:24:11:65:b5:d8, iface eth0.
  # Public NAT forwards 148.113.8.216:20041 → internal 10.10.10.51:22, so sshd stays on 22.
  networking.networkmanager.enable = lib.mkForce false; # override common/hosts/nixos/networking.nix
  networking.useDHCP = false;
  networking.usePredictableInterfaceNames = false; # → "eth0", matches OVH set-name
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.10.10.51";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.10.10.1";
  networking.nameservers = ["1.1.1.1" "1.0.0.1"];

  networking.firewall.enable = lib.mkForce true; # override common layer (firewall off by default)
  networking.firewall.allowedTCPPorts = [22];

  # --- SSH: key-only; root key-login permitted (deploy-rs + recovery path + nixos-anywhere verify) ---
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # QEMU guest agent — clean hypervisor-driven lifecycle/shutdown
  services.qemuGuest.enable = true;

  # --- Login passwords via agenix (yescrypt hashes from infra-nixCfg-secrets) ---
  # The age private key is seeded at /var/lib/agenix/id_ed25519 during provisioning.
  age.identityPaths = ["/var/lib/agenix/id_ed25519"];
  age.secrets."users/div".file = secretsPath + "/users/div.age";
  age.secrets."users/root".file = secretsPath + "/users/root.age";

  # --- Admin user (common layer creates `div`; grant sudo + SSH key + password) ---
  users.users.root = {
    openssh.authorizedKeys.keys = [sshPubKey];
    hashedPasswordFile = config.age.secrets."users/root".path;
  };
  users.users."${config.hostSpec.username}" = {
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [sshPubKey];
    hashedPasswordFile = config.age.secrets."users/div".path;
  };
  security.sudo.enable = true;
}
