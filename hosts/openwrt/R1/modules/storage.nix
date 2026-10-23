_: {
  uci = {
    packages = [
      "blkid"
      "block-mount"
      "e2fsprogs"
      "kmod-fs-exfat"
      "kmod-fs-ext4"
      "losetup"
      "parted"
      "resize2fs"
      "sfdisk"
      "smartmontools"
    ];

    settings.fstab = {
      global = {
        _type = "global";
        anon_swap = "0";
        anon_mount = "0";
        auto_swap = "1";
        auto_mount = "1";
        delay_root = "5";
        check_fs = "0";
      };

      internal = {
        _type = "mount";
        target = "/srv/internal";
        uuid = "3442743b-bdd4-4dfb-8862-b8f4052a2ec6";
        fstype = "ext4";
        options = "rw,noatime";
        enabled = "1";
      };

      nas = {
        _type = "mount";
        target = "/srv/nas";
        uuid = "5F33-30A6";
        fstype = "exfat";
        options = "rw,noatime";
        enabled = "1";
      };
    };

    files = [
      {
        path = "/etc/nuci/reconcile.d/10-storage";
        executable = true;
        content = ''
          #!/bin/sh
          set -eu

          mkdir -p /srv/internal /srv/nas
          block mount
          if grep -qs ' /srv/nas ' /proc/mounts; then
            mount -o remount,rw,noatime /srv/nas
          fi
        '';
      }
    ];
  };
}
