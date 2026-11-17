{inputs, ...}: {
  # T1's 128 GB NVMe, by id so the install can't land on another disk if
  # enumeration changes (/dev/sda on this box is a 0-byte USB card reader).
  # The id embeds the drive's serial, so it lives in the private
  # infra-nixCfg-secrets (`homelab.disks`).
  disko.devices.disk.main.device = inputs.infra-nixCfg-secrets.homelab.disks.T1;
}
