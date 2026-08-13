{lib, ...}: {
  boot.initrd.availableKernelModules = ["uhci_hcd" "xhci_pci" "ehci_pci" "ata_piix" "ahci" "sd_mod" "sr_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  networking.useDHCP = lib.mkDefault true;
}
