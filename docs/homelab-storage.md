# Homelab removable storage

This opt-in NixOS module assigns existing filesystems to stable paths, backs up
consistent service exports to existing restic repositories, and optionally polls
SMART health. It performs no partitioning, formatting, filesystem repair, drive
settings changes, or automatic repository initialization. No host imports or disk
assignments are included. No changes have been deployed.

## Inventory findings (2026-11-20)

Read-only SSH inventory succeeded on all four nodes. Commands used `lsblk`,
`findmnt`, `udevadm info`, and `wipefs --no-act` on USB devices only. macOS was
inspected with `diskutil list`. No filesystems were mounted by the inventory.
Serial numbers, filesystem UUIDs, disk labels and raw SMART reports are excluded
from this document and the inventory tool's output.

| Machine | Existing storage and mounts                                                        | Removable observations                                                       |
| ------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| T1      | 119.2 GiB NVMe; ext4 root/store, FAT boot, encrypted swap                          | No USB disks                                                                 |
| T2      | 238.5 GiB NVMe; ext4 root/store, FAT boot, encrypted swap                          | One zero-capacity USB mass-storage device; no filesystem signatures reported |
| T3      | 238.5 GiB NVMe; ext4 root/store, FAT boot, encrypted swap; service volumes on root | No USB disks                                                                 |
| MON1    | 298.1 GiB rotating SATA; ext4 root/store and FAT boot                              | One zero-capacity Realtek USB reader; no filesystem signatures reported      |
| Mac     | Internal 1 TB physical disk, APFS volumes including Nix Store                      | No external disks                                                            |

`smartctl` is absent on all four nodes; SMART status remains unknown. A
zero-capacity reader is not evidence that one of the requested HDDs is attached.
The two 512 GiB USB3 HDDs, 128 GiB USB2 HDD and usable old flash drives could not
be identified. Their filesystem types, data contents and health are **unknown**.
Do not infer they are blank from this inventory.

Parent follow-up: attach one intended HDD to T3 or MON1, identify which physical
drive was attached, and repeat the inventory. Keep stable identifiers and any
full diagnostic output private. No disk can safely be enabled until its existing
filesystem and data ownership have been reviewed.

## Proposed assignments (pending hardware)

- First 512 GiB USB3 HDD: T3, local service backups after application-consistent
  exports. Keep live databases, k3s state and Attic on existing internal storage
  until a separate migration is reviewed. Backups are expendable only after a
  tested second copy exists; Attic cache content normally need not be backed up.
- Second 512 GiB USB3 HDD: rotated, disconnected second copy. Connect to T3 during
  backup windows to avoid MON1's slower USB path. Rotate physically off-site when
  possible. Two disks permanently connected to one host are one failure domain.
- 128 GiB USB2 HDD: MON1, small cold copies of configuration and service exports,
  subject to measured usable capacity and healthy media. MON1's 2 GiB RAM and
  slower USB make it unsuitable for bulk copies, storage pools or heavy scanners.
- Old flash drives: only verified recovery media or nonessential transport;
  no primary database, swap, or sole backup copy.

T1 and the router are excluded from USB storage duties to preserve routing and
avoid shared USB/controller contention. None of these assignments assumes a
filesystem may be overwritten. Existing filesystems outside ext4/XFS/Btrfs need
an explicit compatibility decision; the module intentionally rejects them.

## Configuration

Import `modules/hosts/nixos/homelab-storage.nix` explicitly on an appropriate
host, coordinated with the parent. It is disabled by default, including each
volume. Suggested first configuration **after identification**:

```nix
{ inputs, ... }: {
  imports = [ ../../../modules/hosts/nixos/homelab-storage.nix ];
  homelab.storage = {
    enable = true;
    volumes.services = {
      enable = true;
      # Proposed private-input field; it must be populated from actual inventory.
      device = inputs.infra-nixCfg-secrets.homelab.storage.T3.services.device;
      fsType = "ext4"; # Replace only with the observed supported filesystem type.
      readOnly = true;
      # SMART remains disabled until bridge support and whole-disk ID are known.
    };
  };
}
```

That import path is relative to a host module in `hosts/nixos/<host>/`. The
private input field above does not exist yet and is an integration example,
not an enabled host assignment. UUID paths are preferred for mount identity;
SMART needs a whole-disk `/dev/disk/by-id/...` path, never a partition.

Mounts live under `/srv/removable/<name>`. They use `nofail`, bounded device and
mount timeouts, and automount with idle unmounting. Disable `automount` for cold
media: `noauto` prevents an incidental path access from mounting it. Neither
mode makes the filesystem required for boot. Read-only ext4 uses `noload`, XFS
uses `norecovery`, and Btrfs uses `nologreplay`, preventing recovery writes during
initial inspection. Dirty filesystems may consequently fail to mount, or expose
an inconsistent pre-replay view: stop and review, never auto-repair. Filesystem
checks and automatic formatting are disabled for every assigned volume.

After the parent coordinates writable use and an existing restic repository is
prepared in a separately reviewed step, the volume may additionally set:

```nix
readOnly = false;
backup = {
  enable = true;
  paths = [ "/var/backup-export" ];
  passwordFile = config.age.secrets.storage-restic.path;
  calendar = "*-*-* 03:30:00"; # null for manually started cold backup jobs
};
smart = {
  enable = true;
  device = inputs.infra-nixCfg-secrets.homelab.storage.T3.services.smartDevice;
  deviceType = "sat"; # Only after a read-only probe confirms bridge support.
};
```

Use the existing agenix convention: encrypted material in the private secrets
input, `age.secrets.storage-restic.file` pointing to its `.age` file, and its
runtime `.path` as `passwordFile`. The module accepts only `/run/agenix/...`
password paths; never put password strings, `builtins.readFile` results or
credentials into Nix. Keep encryption recovery material separately backed up.
No new secret is provisioned by this change.

The service `restic-backups-storage-<name>` requires the mount and verifies
its resolved block-device identity and filesystem type before any restic action.
It also binds the backup service lifetime to the mount unit, stopping the writer
when the mount disappears. It requires an existing, nonsymlink `restic` directory on the disk. Missing
media or a wrong mount fails the job instead of writing into the root disk.
Initialization, pruning and persistent catch-up timers are disabled. A post-backup
restic structural check runs; a full read/restore test remains a separate task.
Disconnected cold media should use `calendar = null` and a parent-coordinated
manual service start. Scheduled backup dependencies can mount `noauto` volumes.

Source paths must be explicit absolute local exports outside `/srv/removable`;
`/` is rejected to prevent accidental recursion. Paths are administrator-owned
configuration. Prepare and validate application-consistent database exports
before scheduling. This module provides local backups, not cross-host copying:
MON1 needs separately coordinated export transfer before backing up T3 data.
There is no implicit network listener or router workload.

## Health and recovery

SMART health polling uses `smartctl -n standby -H -j` hourly, with no self-tests
or setting changes. It allows only the explicitly configured whole disk and
publishes `homelab_storage_smart_healthy{volume="<name>"}` through node exporter's
textfile collector: `1` passes, `0` fails, `-1` means unavailable/unsupported or
sleeping. Serial numbers and raw reports never become metric labels. No separate
exporter port is opened. MON1's existing node scrape covers these metrics once
host imports and activation are coordinated. Monitor `!= 1`, missing/stale
textfile metrics, node filesystem free space/read-only state, and failed restic
systemd units; alert rules are not installed by this module.

No `smartd` daemon or GUI packages are added. Disabled SMART polling does not
install or run SMART utilities. Filesystem health relies on existing node
filesystem metrics and kernel/journal errors. Read-only probes cannot establish
full filesystem integrity. Offline checks, repairs, SMART self-tests and write
performance tests need separate review; do not run them automatically. Restic
checks establish repository structure, not application consistency. Test restoring
selected files to a separate reviewed destination and record results privately.

## Verification and handoff

Run inventory as root on Linux (util-linux and udev required; `smartctl` plus
Python 3 optional); on macOS it invokes only `diskutil list`:

```sh
sudo bash utils/storage/inventory.sh
# SSH transport: use the node's already pinned known-hosts file and authorized key.
```

Inventory is always read-only; there is no apply mode. Device IDs needed for
configuration must be inspected separately into private notes. Public inventory
reports do not identify disks uniquely.

`tests/homelab-storage.nix` uses only `lib.evalModules`, synthetic package paths
and option stubs. It checks disabled defaults, recovery-write suppression,
format/check suppression, unstable IDs, duplicates, invalid secrets, readonly
backup rejection, whole-disk SMART validation and backup mount guards. It does
not build a host or claim to test actual disk behavior. To run this small test
with an available nixpkgs source:

```sh
nix-instantiate --eval --strict --json --expr \
  'import ./tests/homelab-storage.nix { lib = import /path/to/nixpkgs/lib; }'
```

The fixture passed locally; shell syntax and read-only inventory passed on all
four nodes, and `nix fmt` ran on changed files. Full host evaluation/builds belong
on GitHub Actions per `.apm/instructions/ci-eval.instructions.md`. Since no host
imports the module yet, existing host CI alone does not validate an enabled
configuration. Parent integration must evaluate the actual identified assignment
on Actions before activation. No local heavy evaluations, deployment builds,
merges, activations, or disk writes were performed.

Primary references used for implementation: [systemd mount dependencies and
fstab options](https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html),
[NixOS restic module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/backup/restic.nix),
and [NixOS filesystem module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/tasks/filesystems.nix).
