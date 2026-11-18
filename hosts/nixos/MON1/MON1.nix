# MON1 — Lenovo S100 (Intel Atom, 2 GiB RAM), formerly the OpenWrt router
# "R1" (its UCI config stays in hosts/openwrt/R1 as a rollback reference).
# Now the home lab's monitoring node; see monitoring.nix. It sits off the
# router on purpose, so it can still alert when T1 is down.
_: {
  # The S100's firmware may be legacy-BIOS only, so GRUB is installed for both
  # BIOS (via the EF02 partition in disko.nix) and UEFI (as removable media,
  # which needs no NVRAM entry).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # NetworkManager (common layer) holds the lease; dhcpcd on top of it was a
  # second client on the same port.
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;
  networking.networkmanager.ensureProfiles.profiles.homelab-wired = {
    connection = {
      id = "homelab-wired";
      type = "ethernet";
      interface-name = "enp1s0";
      autoconnect = true;
      autoconnect-priority = 100;
      autoconnect-retries = 0;
    };
    ipv4.method = "auto";
    ipv6.method = "auto";
  };

  # 2 GiB of RAM: compressed swap in RAM before touching the disk.
  zramSwap.enable = true;
}
