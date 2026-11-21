# Keep enabled-module coverage on the native Linux CI runner, without disks or a VM.
{
  inputs,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") (let
      evaluated = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ../modules/hosts/nixos/homelab-storage.nix
          {
            system.stateVersion = "26.05";
            networking.hostName = "storage-eval-only";
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            homelab.storage = {
              enable = true;
              volumes = {
                services = {
                  enable = true;
                  device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000001";
                  readOnly = false;
                  smart = {
                    enable = true;
                    device = "/dev/disk/by-id/usb-CI_DUMMY_DISK";
                    deviceType = "sat";
                  };
                  backup = {
                    enable = true;
                    paths = ["/var/backup-export"];
                    passwordFile = "/run/agenix/ci-dummy-password";
                  };
                };
                inspection = {
                  enable = true;
                  device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000002";
                };
                cold = {
                  enable = true;
                  device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000003";
                  readOnly = false;
                  automount = false;
                  backup = {
                    enable = true;
                    paths = ["/etc"];
                    passwordFile = "/run/agenix/ci-dummy-password";
                    calendar = null;
                  };
                };
              };
            };
          }
        ];
      };
      cfg = evaluated.config;
      # Force the real complete NixOS configuration, including option types,
      # assertions and generated systemd services/timers, before creating the check.
      # This is evaluation only: never reference the system derivation as an input.
      systemDrv = cfg.system.build.toplevel.drvPath;
      backup = cfg.services.restic.backups.storage-services;
      inspected = cfg.fileSystems."/srv/removable/inspection";
      report = {
        fullNixOS = builtins.unsafeDiscardStringContext systemDrv;
        scheduledBackup = backup.initialize == false && backup.timerConfig.Persistent == false;
        realBackupService = cfg.systemd.services.restic-backups-storage-services.serviceConfig.Type == "oneshot";
        realBackupTimer = cfg.systemd.timers.restic-backups-storage-services.timerConfig.OnCalendar == "*-*-* 03:30:00";
        manualColdBackup = cfg.services.restic.backups.storage-cold.timerConfig == null && !(builtins.hasAttr "restic-backups-storage-cold" cfg.systemd.timers);
        readOnlyNoReplay = lib.elem "ro" inspected.options && lib.elem "noload" inspected.options;
        noFormattingOrRepair = lib.all (v: !v.autoFormat && v.noCheck) (map (name: cfg.fileSystems."/srv/removable/${name}") ["services" "inspection" "cold"]);
        smartService = cfg.systemd.services.homelab-storage-health.serviceConfig.Type == "oneshot";
        smartTimer = cfg.systemd.timers.homelab-storage-health.timerConfig.OnUnitActiveSec == "1h";
        nodeTextfile = lib.elem "textfile" cfg.services.prometheus.exporters.node.enabledCollectors;
      };
      successful = builtins.deepSeq report (lib.all (v: v) (lib.attrValues (builtins.removeAttrs report ["fullNixOS"])));
    in {
      homelab-storage = assert lib.assertMsg successful "Enabled homelab storage NixOS evaluation assertions failed";
        pkgs.runCommandNoCC "homelab-storage-nixos-evaluation" {
          # Context was stripped above: building this tiny receipt cannot build,
          # realize, boot or activate the evaluated system or access any disk.
          reportJSON = builtins.toJSON report;
          passAsFile = ["reportJSON"];
        } ''
          mkdir -p "$out"
          cp "$reportJSONPath" "$out/evaluation.json"
        '';
    });
  };
}
