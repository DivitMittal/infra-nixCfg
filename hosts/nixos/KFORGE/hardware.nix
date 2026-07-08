{lib, ...}: {
  boot.initrd.availableKernelModules = ["virtio_pci" "virtio_blk" "virtio_scsi" "virtio_net" "ahci" "sd_mod" "xhci_pci"];
  boot.initrd.kernelModules = [];

  networking.useDHCP = lib.mkDefault true;

  # system.build.vm overrides the disk; this keeps the bare toplevel buildable.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
