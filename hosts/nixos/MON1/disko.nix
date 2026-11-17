{inputs, ...}: {
  disko.devices.disk.main = {
    # Stable by-id path of the S100's internal HDD; it embeds the drive's
    # serial, so it lives in the private input.
    device = inputs.infra-nixCfg-secrets.homelab.disks.MON1;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # GRUB's BIOS stage on a GPT disk; disko adds this device to
        # boot.loader.grub.devices automatically.
        boot = {
          size = "1M";
          type = "EF02";
        };
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
