{inputs, ...}: {
  # VPS0 Oracle Cloud A1 Flex: single OCI block volume, UEFI boot. Its by-id
  # path lives in the private infra-nixCfg-secrets (`homelab.disks`).
  disko.devices = {
    disk.main = {
      device = inputs.infra-nixCfg-secrets.homelab.disks.VPS0;
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
