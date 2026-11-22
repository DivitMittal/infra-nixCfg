{inputs, ...}: {
  # The stable NVMe identity contains a serial and belongs in the private input.
  disko.devices.disk.main.device = inputs.infra-nixCfg-secrets.homelab.disks.T2;
}
