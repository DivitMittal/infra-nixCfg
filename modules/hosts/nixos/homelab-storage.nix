# Explicit import only: no host gets a disk assignment from this module.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.homelab.storage;
  volumes = lib.filterAttrs (_: v: v.enable) cfg.volumes;
  stable = s: builtins.match "/dev/disk/by-(id|uuid)/[A-Za-z0-9_.:+-]+" s != null && !(lib.elem (baseNameOf s) ["." ".."]);
  runtimeSecret = s: builtins.match "/run/agenix/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*" s != null;
  backupVolumes = lib.filterAttrs (_: v: v.backup.enable) volumes;
  smartVolumes = lib.filterAttrs (_: v: v.smart.enable) volumes;
  mountPath = name: "/srv/removable/${name}";
  repository = name: "${mountPath name}/restic";
  guard = name: v: ''
    #!${pkgs.runtimeShell}
    set -eu
    target=${lib.escapeShellArg (mountPath name)}
    expected=${lib.escapeShellArg v.device}
    # An autofs mount alone is not proof that the actual disk is mounted.
    ${pkgs.util-linux}/bin/mountpoint -q "$target"
    actual=$(${pkgs.util-linux}/bin/findmnt --nofsroot -rn -M "$target" -o SOURCE)
    test "$(${pkgs.coreutils}/bin/readlink -f "$actual")" = "$(${pkgs.coreutils}/bin/readlink -f "$expected")"
    test "$(${pkgs.util-linux}/bin/findmnt --nofsroot -rn -M "$target" -o FSTYPE)" = ${lib.escapeShellArg v.fsType}
    test -d "$target/restic"
    test ! -L "$target/restic"
  '';
in {
  options.homelab.storage = {
    enable = lib.mkEnableOption "explicitly identified removable homelab storage";
    volumes = mkOption {
      default = {};
      type = types.attrsOf (types.submodule {
        options = {
          enable = lib.mkEnableOption "this inventoried volume";
          device = mkOption {
            type = types.str;
            description = "Existing filesystem's stable /dev/disk/by-id or by-uuid path; keep identifiers in the private input.";
          };
          fsType = mkOption {
            type = types.enum ["ext4" "xfs" "btrfs"];
            default = "ext4";
          };
          readOnly = mkOption {
            type = types.bool;
            default = true;
            description = "Disable only after reviewing existing data and assigning the disk.";
          };
          automount = mkOption {
            type = types.bool;
            default = true;
            description = "For cold disks disable this and mount explicitly during a backup window.";
          };
          smart = {
            enable = lib.mkEnableOption "read-only SMART health polling (no tests or setting changes)";
            device = mkOption {
              type = types.str;
              default = "";
              description = "Whole disk /dev/disk/by-id path, not a partition.";
            };
            deviceType = mkOption {
              type = types.enum ["auto" "sat" "scsi"];
              default = "auto";
            };
          };
          backup = {
            enable = lib.mkEnableOption "backups into an already initialized local restic repository";
            paths = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Consistent local snapshots or stopped-service exports; never raw live databases.";
            };
            passwordFile = mkOption {
              type = types.str;
              default = "";
              description = "Runtime /run/agenix secret path, never builtins.readFile.";
            };
            calendar = mkOption {
              type = types.nullOr types.str;
              default = "*-*-* 03:30:00";
              description = "Set null for a manually started cold-backup job.";
            };
          };
        };
      });
    };
  };
  config = lib.mkIf cfg.enable {
    assertions =
      lib.concatLists (lib.mapAttrsToList (name: v: [
          {
            assertion = builtins.match "[a-z][a-z0-9-]*" name != null;
            message = "Storage names must be lowercase safe path components.";
          }
          {
            assertion = stable v.device;
            message = "Storage ${name}: an inventoried stable ID/UUID is required.";
          }
          {
            assertion = !v.smart.enable || (lib.hasPrefix "/dev/disk/by-id/" v.smart.device && stable v.smart.device && builtins.match ".*-part[0-9]+" v.smart.device == null);
            message = "Storage ${name}: SMART requires a whole-disk stable ID.";
          }
          {
            assertion = !v.backup.enable || (!v.readOnly && v.backup.paths != [] && runtimeSecret v.backup.passwordFile);
            message = "Storage ${name}: backups require explicit writable access, source paths and an agenix runtime password.";
          }
          {
            assertion = lib.all (p: lib.hasPrefix "/" p && !(lib.hasPrefix "/srv/removable" p) && p != "/") v.backup.paths;
            message = "Storage ${name}: use explicit absolute backup sources outside removable storage, not /.";
          }
        ])
        volumes)
      ++ [
        {
          assertion = lib.length (lib.unique (map (v: v.device) (lib.attrValues volumes))) == lib.length (lib.attrValues volumes);
          message = "Do not assign the same storage device to multiple volumes.";
        }
      ];
    fileSystems = lib.mapAttrs' (name: v:
      lib.nameValuePair (mountPath name) {
        inherit (v) device fsType;
        autoFormat = false;
        neededForBoot = false;
        # Boot/activation must never repair or replay an unidentified disk.
        noCheck = true;
        options =
          ["nofail" "nodev" "nosuid" "noexec" "x-systemd.device-timeout=10s" "x-systemd.mount-timeout=30s"]
          ++ lib.optionals v.automount ["x-systemd.automount" "x-systemd.idle-timeout=10min"]
          ++ lib.optional (!v.automount) "noauto"
          ++ (
            if v.readOnly
            then ["ro"] ++ lib.optional (v.fsType == "ext4") "noload" ++ lib.optional (v.fsType == "xfs") "norecovery" ++ lib.optional (v.fsType == "btrfs") "nologreplay"
            else ["rw"]
          );
      })
    volumes;
    services.restic.backups = lib.mapAttrs' (name: v:
      lib.nameValuePair "storage-${name}" {
        repository = repository name;
        inherit (v.backup) paths passwordFile;
        initialize = false;
        createWrapper = false;
        # Retention deletion is a separate reviewed policy, never implicit.
        pruneOpts = [];
        checkOpts = ["--with-cache"];
        backupPrepareCommand = guard name v;
        timerConfig =
          if v.backup.calendar == null
          then null
          else {
            OnCalendar = v.backup.calendar;
            Persistent = false;
            RandomizedDelaySec = "20m";
          };
      })
    backupVolumes;
    systemd.services =
      lib.mapAttrs' (name: _v:
        lib.nameValuePair "restic-backups-storage-${name}" {
          unitConfig = {
            RequiresMountsFor = [(mountPath name)];
            # Stop the writer if systemd loses the mount after the initial guard.
            BindsTo = ["srv-removable-${lib.replaceStrings ["-"] ["\\x2d"] name}.mount"];
          };
          serviceConfig = {
            Nice = 15;
            IOSchedulingClass = "idle";
          };
        })
      backupVolumes
      // lib.optionalAttrs (smartVolumes != {}) {
        homelab-storage-health = {
          description = "Read-only health probes for explicitly assigned disks";
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
          };
          script = ''
            set -eu
            dir=/var/lib/prometheus-node-exporter-text-files
            install -d -m 0755 "$dir"
            tmp=$(mktemp "$dir/.storage.XXXXXX")
            trap 'rm -f "$tmp"' EXIT
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: v: ''
                # smartctl's bitmask exit code may be nonzero with valid JSON.
                data=$(${pkgs.smartmontools}/bin/smartctl -n standby -H -j -d ${lib.escapeShellArg v.smart.deviceType} ${lib.escapeShellArg v.smart.device} 2>/dev/null) || :
                healthy=$(printf '%s' "$data" | ${pkgs.jq}/bin/jq -er 'if .smart_status.passed == true then 1 elif .smart_status.passed == false then 0 else -1 end') || healthy=-1
                printf 'homelab_storage_smart_healthy{volume="%s"} %s\n' ${lib.escapeShellArg name} "$healthy" >> "$tmp"
              '')
              smartVolumes)}
            chmod 0644 "$tmp"
            mv "$tmp" "$dir/homelab-storage.prom"
          '';
        };
      };
    systemd.timers.homelab-storage-health = lib.mkIf (smartVolumes != {}) {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "1h";
      };
    };
    services.prometheus.exporters.node = lib.mkIf (smartVolumes != {}) {
      enable = true;
      enabledCollectors = ["textfile"];
      extraFlags = ["--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files"];
    };
  };
}
