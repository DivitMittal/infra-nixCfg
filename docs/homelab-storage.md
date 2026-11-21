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
| T1      | 119.2 GiB NVMe; ext4 root/store, FAT boot, encrypted swap                          | No USB block device enumerated                                                                 |
| T2      | 238.5 GiB NVMe; ext4 root/store, FAT boot, encrypted swap                          | One zero-capacity USB mass-storage device; no filesystem signatures reported |
| T3      | 238.5 GiB NVMe; ext4 root/store, FAT boot, encrypted swap; service volumes on root | No USB block device enumerated                                                                 |
| MON1    | 298.1 GiB rotating SATA; ext4 root/store and FAT boot                              | One zero-capacity Realtek USB reader; no filesystem signatures reported      |
| Mac     | Internal 1 TB physical disk, APFS volumes including Nix Store                      | No external disk enumerated                                                            |

The user confirms a 512 GiB USB HDD is connected to T3 and a 128 GiB USB
HDD is connected to T2 (now or previously). The block-device inventory is a
**detection failure**, not evidence that these physical disks are absent.
`smartctl` and `lsusb` are not on the default PATH on T2/T3. No cached
`lsusb` executable was found; enumeration was inspected via sysfs, udev and
kernel journals instead. T3 has a cached `smartctl` binary, but no USB block
device to query. SMART status remains unknown.

Read-only diagnostic follow-up found:

- **T2:** current zero-capacity `/dev/sda` is vendor/product `1908:0226`,
  Generic Mass-Storage, removable, on USB path `1-4.1.2.4`; the kernel reports
  `Media removed, stopped polling`. This device is separate from hub port
  `2-4.4`, which repeatedly failed descriptor/configuration reads with `-71`
  and `-110` on November 19, 05:22–05:26 IST. That failing port briefly read
  vendor/product `1058:0740` before configuration failure and disconnect.
  Its exact physical identity/capacity is not established.
- **T3:** current USB enumeration contains VIA USB2/USB3 hubs and an Amazon
  device, but no storage interface and no USB block device. On November 19,
  16:32–16:33 IST, hub port `2-4.3` failed descriptor reads (`-32`), setup
  addresses (`-71`) and enumeration. There is insufficient identity data to
  associate that failed port conclusively with the reported HDD.
- Both inspected hubs report runtime-suspended SuperSpeed paths; this alone
  does not establish a power fault. No over-current messages or disk-specific
  UAS resets were found in the filtered current-boot logs. T2 registers UAS,
  while its existing zero-capacity device uses `usb-storage`; descriptor errors
  occur before a storage driver can bind.

The [Linux USB error documentation](https://docs.kernel.org/driver-api/usb/error-codes.html)
explains protocol/stall/timeout failures and warns that controllers cannot always
distinguish device, cable and disconnect faults. Cable/hub/power/enclosure/drive
faults remain candidates, not a confirmed diagnosis. No resets, rebinds, power
setting writes, rescans, mounts or repairs were performed. Historical kernel
messages about automatic power cycles describe past kernel behavior, not actions
performed during this investigation.

Parent follow-up: identify the physical cable/hub path for the T3 512 GiB and
T2 128 GiB HDDs. Coordinate a known-good data cable/direct host port/power check
with the user, avoiding the hub branch carrying T2 networking. Do not reset a
shared hub. Repeat read-only enumeration after any user-coordinated physical
change. Filesystem types, UUIDs and existing data cannot be probed until the
bridge exposes usable media. Preserve actual stable IDs in the private input
once observed; no identifiers or assignments may be invented from failed USB
messages. Formatting is not authorized.

## Proposed assignments (pending successful detection)

- First 512 GiB USB3 HDD: T3, local service backups after application-consistent
  exports. Keep live databases, k3s state and Attic on existing internal storage
  until a separate migration is reviewed. Backups are expendable only after a
  tested second copy exists; Attic cache content normally need not be backed up.
- Second 512 GiB USB3 HDD: rotated, disconnected second copy. Connect to T3 during
  backup windows to avoid MON1's slower USB path. Rotate physically off-site when
  possible. Two disks permanently connected to one host are one failure domain.
- 128 GiB USB2 HDD: user reports it connected to T2; diagnose there first. A
  later user-coordinated MON1 assignment could hold small cold configuration and service exports,
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
four nodes, and `nix fmt` ran on changed files. The macOS command uses
`/usr/sbin/diskutil` explicitly so it works with a minimal PATH.

`flake/checks-homelab-storage.nix` adds `checks.x86_64-linux.homelab-storage`
through the existing flake-parts auto-import/check conventions. On the native
GitHub Actions flake-check runner it evaluates a minimal **real NixOS system**
with this module enabled: a dummy writable backup+SMART volume, a read-only
inspection volume, and a manual cold backup volume. Forcing
`system.build.toplevel.drvPath` evaluates real option types, assertions and
generated restic/systemd configuration. The check asserts scheduled/manual timer
behavior, service types, read-only options, no formatting/repair and textfile
collector integration. Its tiny derivation only copies an evaluation receipt;
the evaluated system's derivation context is stripped, so it is not a build
input and no system, disk or VM is realized or activated.

Full evaluation/build checks run on GitHub Actions per
`.apm/instructions/ci-eval.instructions.md`; do not run the enabled fixture or
`nix flake check` locally. No deployed host imports the module, and actual stable
IDs remain pending successful hardware detection and private inventory. Parent
integration must evaluate the actual identified assignment on Actions before
activation. No local heavy evaluations, deployment builds, merges, activations,
or disk writes were performed.

Primary references used for implementation: [systemd mount dependencies and
fstab options](https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html),
[NixOS restic module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/backup/restic.nix),
and [NixOS filesystem module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/tasks/filesystems.nix).
