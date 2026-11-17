# MON1 — Lenovo S100 (Intel Atom, 2 GiB RAM), formerly the OpenWrt router
# "R1" (its UCI config stays in hosts/openwrt/R1 as a rollback reference).
# Now the home lab's monitoring node; see monitoring.nix. It sits off the
# router on purpose, so it can still alert when T1 is down.
{lib, ...}: {
  # The S100's firmware may be legacy-BIOS only, so GRUB is installed for both
  # BIOS (via the EF02 partition in disko.nix) and UEFI (as removable media,
  # which needs no NVRAM entry).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.useDHCP = lib.mkDefault true;

  # 2 GiB of RAM: compressed swap in RAM before touching the disk.
  zramSwap.enable = true;
}
