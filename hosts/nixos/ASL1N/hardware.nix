{
  inputs,
  lib,
  config,
  ...
}: let
  # The module's default finds /boot/asahi via builtins.pathExists, which only
  # succeeds when evaluating on this machine; elsewhere (CI) it's null.
  firmwareDir = config.hardware.asahi.peripheralFirmwareDirectory;
in {
  imports = [
    inputs.nixos-apple-silicon.nixosModules.default
  ];

  hardware.asahi = {
    enable = true;
    # Extract Wi-Fi/Bluetooth firmware from the Asahi EFI partition at build
    # time, when it's reachable (asserting otherwise breaks off-host eval).
    extractPeripheralFirmware = firmwareDir != null;
  };

  warnings = lib.optional (firmwareDir == null) ''
    ASL1N: Asahi peripheral firmware not found (/boot/asahi); this build has
    no Wi-Fi/Bluetooth firmware. Expected only when evaluating off-host.
  '';

  boot.initrd.availableKernelModules = ["nvme" "usb_storage" "usbhid" "xhci_pci"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  networking.useDHCP = lib.mkDefault true;

  # EFI partition created by the Asahi Linux installer (contains U-Boot — do not reformat).
  # Identify the correct partition number with: lsblk -f /dev/nvme0n1
  # Update the device path before running nixos-install.
  fileSystems."/boot" = {
    device = "/dev/nvme0n1p4"; # Adjust partition number to match your Asahi layout
    fsType = "vfat";
    options = ["umask=0077" "noatime"];
    neededForBoot = true;
  };
}
