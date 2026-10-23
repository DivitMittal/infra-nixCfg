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
  # --- Boot: Germany KVM VPS is legacy BIOS; disko.nix's EF02 partition registers /dev/sda with GRUB ---
  boot.loader.grub.enable = true;

  # virtio drivers for KVM disk/net/balloon + generic SATA/USB storage modules
  boot.initrd.availableKernelModules = ["ahci" "sd_mod" "sr_mod" "xhci_pci" "uhci_hcd" "ehci_pci" "ata_piix"];
  boot.initrd.kernelModules = ["virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net" "virtio_balloon"];

  # --- Networking: IPv6-only direct public address ---
  # Germany KVM VPS for server/background workloads (~200ms RTT): 2a0e:97c0:3e3:34d::1/64, MAC 4a:ca:80:0a:0f:ce, iface eth0.
  # The default gateway is link-local, so the interface must be specified.
  networking.networkmanager.enable = lib.mkForce false; # override common/hosts/nixos/networking.nix
  networking.useDHCP = false;
  networking.usePredictableInterfaceNames = false; # → "eth0", matches provider set-name
  networking.interfaces.eth0.ipv6.addresses = [
    {
      address = "2a0e:97c0:3e3:34d::1";
      prefixLength = 64;
    }
  ];
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "eth0";
  };
  networking.nameservers = ["2606:4700:4700::1111" "2606:4700:4700::1001"];
  networking.search = ["v69412.datalix.de"];

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
  # Mullvad WG private key — decrypted at activation by ragenix, same path-input
  # mechanism as users/*.age above (works under deploy-rs remoteBuild because
  # deploy-rs archives the flake closure, including path inputs, to the remote).
  age.secrets."mullvad".file = secretsPath + "/mullvad/wg-private.age";

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

  # --- Mullvad VPN (split tunnel: IPv4 via Mullvad, IPv6 native on eth0) ---
  # Gives VPS2 IPv4 egress so it can reach github.com (IPv4-only).
  # Private key from agenix (age.secrets."mullvad" above) — never stored in the
  # nix store as plaintext or committed to this repo.
  # Relay: de-fra-wg-001 (Frankfurt). Address 10.64.205.203 derived from account
  # 0901578829610741 (XOR formula) — verify vs UI.
  networking.wg-quick.interfaces.mullvad = {
    privateKeyFile = config.age.secrets."mullvad".path;
    address = ["10.64.205.203/32"];
    listenPort = 51820;
    peers = [
      {
        publicKey = "HQHCrq4J6bSpdW1fI5hR/bvcrYa6HgGgwaa5ZY749ik=";
        endpoint = "[2a03:1b20:6:f011::f001]:51820";
        allowedIPs = ["0.0.0.0/0"];
        persistentKeepalive = 25;
      }
    ];
  };
  networking.firewall.allowedUDPPorts = [51820];
}
