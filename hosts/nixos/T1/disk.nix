_: {
  # From T1's facter report: a 128 GB NVMe. /dev/sda on this box is a
  # 0-byte USB card reader, so the shared /dev/sda default would be wrong.
  # by-id so the install can't land on another disk if enumeration changes.
  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-CONSISTENT_NVME_S6_128GB_2024092009453";
}
