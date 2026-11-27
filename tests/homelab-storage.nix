# Cheap lib.evalModules checks only; full NixOS evaluation belongs on Actions.
{lib}: let
  inherit (lib) mkOption types;
  evaluate = storage:
    (lib.evalModules {
      specialArgs.pkgs = {
        runtimeShell = "/bin/sh";
        util-linux = "/test/util-linux";
        coreutils = "/test/coreutils";
        smartmontools = "/test/smartmontools";
        jq = "/test/jq";
      };
      modules = [
        ../modules/hosts/nixos/homelab-storage.nix
        {
          options = {
            assertions = mkOption {
              type = types.listOf types.anything;
              default = [];
            };
            fileSystems = mkOption {
              type = types.attrsOf types.anything;
              default = {};
            };
            services = mkOption {
              type = types.attrsOf types.anything;
              default = {};
            };
            systemd = mkOption {
              type = types.attrsOf types.anything;
              default = {};
            };
          };
          config.homelab.storage = storage;
        }
      ];
    }).config;
  volume = {
    enable = true;
    device = "/dev/disk/by-uuid/example";
  };
  withVolume = v:
    evaluate {
      enable = true;
      volumes.backup = v;
    };
  passes = c: lib.all (a: a.assertion) c.assertions;
  readOnly = withVolume volume;
  writable = withVolume (volume
    // {
      readOnly = false;
      backup = {
        enable = true;
        paths = ["/var/backup-export"];
        passwordFile = "/run/agenix/storage-restic";
      };
    });
  job = writable.services.restic.backups.storage-backup;
  checks = {
    disabled = (evaluate {}).fileSystems == {};
    readonly = passes readOnly && lib.elem "ro" readOnly.fileSystems."/srv/removable/backup".options && lib.elem "noload" readOnly.fileSystems."/srv/removable/backup".options;
    noFormatting = !readOnly.fileSystems."/srv/removable/backup".autoFormat && readOnly.fileSystems."/srv/removable/backup".noCheck;
    unstableRejected = !passes (withVolume (volume // {device = "/dev/sdb1";}));
    readonlyBackupRejected = !passes (withVolume (volume // {backup.enable = true;}));
    storeSecretRejected =
      !passes (withVolume (volume
        // {
          readOnly = false;
          backup = {
            enable = true;
            paths = ["/etc"];
            passwordFile = "/nix/store/password";
          };
        }));
    traversalSecretRejected =
      !passes (withVolume (volume
        // {
          readOnly = false;
          backup = {
            enable = true;
            paths = ["/etc"];
            passwordFile = "/run/agenix/../../etc/password";
          };
        }));
    smartPartitionRejected =
      !passes (withVolume (volume
        // {
          smart = {
            enable = true;
            device = "/dev/disk/by-id/example-part1";
          };
        }));
    duplicateRejected =
      !passes (evaluate {
        enable = true;
        volumes = {
          one = volume;
          two = volume;
        };
      });
    coldDisk = lib.elem "noauto" (withVolume (volume // {automount = false;})).fileSystems."/srv/removable/backup".options;
    backupGuarded = passes writable && !job.initialize && job.pruneOpts == [] && lib.hasInfix "set -eu" job.backupPrepareCommand && lib.hasInfix "readlink -f" job.backupPrepareCommand && lib.hasInfix "test ! -L" job.backupPrepareCommand;
    manualColdBackup = let
      c = withVolume (volume
        // {
          readOnly = false;
          automount = false;
          backup = {
            enable = true;
            paths = ["/etc"];
            passwordFile = "/run/agenix/restic";
            calendar = null;
          };
        });
    in
      passes c && c.services.restic.backups.storage-backup.timerConfig == null;
    lossStopsWriter = writable.systemd.services.restic-backups-storage-backup.unitConfig.BindsTo == ["srv-removable-backup.mount"];
    smartPrivate = let
      c = withVolume (volume
        // {
          smart = {
            enable = true;
            device = "/dev/disk/by-id/example";
          };
        });
    in
      passes c && lib.hasInfix "homelab_storage_smart_healthy" c.systemd.services.homelab-storage-health.script;
  };
in
  assert lib.assertMsg (lib.all (x: x) (lib.attrValues checks)) (builtins.toJSON checks); checks
