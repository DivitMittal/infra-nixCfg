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
  # --- Boot: Oracle Cloud A1 Flex uses UEFI; install GRUB as removable media because EFI vars are unavailable. ---
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    efiInstallAsRemovable = true;
    extraConfig = ''
      serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
      terminal_input serial console
      terminal_output serial console
    '';
  };
  boot.loader.efi.canTouchEfiVariables = false;

  # virtio drivers for OCI paravirtualized SCSI disk, network, console, rng, and balloon devices
  boot.initrd.availableKernelModules = ["xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod"];
  boot.initrd.kernelModules = ["virtio_pci" "virtio_scsi" "virtio_net" "virtio_balloon" "virtio_console" "virtio_rng"];

  # OCI serial console: show both GRUB and kernel logs, and keep a login getty available for recovery.
  boot.kernelParams = ["console=tty0" "console=ttyS0,115200n8"];
  systemd.services."serial-getty@ttyS0".enable = true;

  # --- Networking: OCI DHCPv4 on the primary VNIC; match by MAC so interface renames do not matter. ---
  networking.networkmanager.enable = lib.mkForce false; # override common/hosts/nixos/networking.nix
  networking.useDHCP = false;
  systemd.network = {
    enable = true;
    networks."10-oci-primary" = {
      matchConfig.MACAddress = "02:00:17:05:eb:38";
      linkConfig.MTUBytes = "9000";
      networkConfig = {
        DHCP = "ipv4";
        LinkLocalAddressing = "ipv6";
      };
      dhcpV4Config = {
        UseDNS = true;
        UseRoutes = true;
      };
    };
  };

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
