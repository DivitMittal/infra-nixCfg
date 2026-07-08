# KFORGE is the Kernel Forge proving host: QEMU/virtio-first, never deployed,
# rebuilt and discarded per kernel iteration.
_: {
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  # Smoke-test access into the proving VM.
  services.openssh.enable = true;

  # Clean hypervisor-driven lifecycle (shutdown/reset between kernel iterations).
  services.qemuGuest.enable = true;
}
