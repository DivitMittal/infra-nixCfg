# HP t640 thin clients (T1, T2, T3): AMD Ryzen Embedded, UEFI, one SATA
# M.2 2242 SSD. Confirm the disk with `lsblk` from the PXE shell (or
# `bootstrap-remote <host> --check`) before a destructive install; override
# disko.devices.disk.main.device per host if it isn't /dev/sda.
{lib, ...}: {
  imports = [./hp-bios.nix];

  hardware.hpBiosInventory.enable = lib.mkDefault true;
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Safe default until the host's facter.json supersedes it.
  boot.kernelModules = ["kvm-amd"];

  networking.useDHCP = lib.mkDefault true;

  disko.devices.disk.main = {
    device = lib.mkDefault "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        swap = {
          size = "4G";
          content = {
            type = "swap";
            randomEncryption = true;
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
