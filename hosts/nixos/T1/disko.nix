_: {
  # HP t640: single SATA M.2 2242 SSD, confirm the exact device via `lsblk`
  # (or `bootstrap-remote T1 --target ... --check`) before a destructive install.
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
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
  };
}
