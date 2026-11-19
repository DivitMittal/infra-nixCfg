# HP t640 BIOS and UEFI boot management

The t640 profile (`hosts/nixos/_homelab/t640.nix`) imports two independent
modules:

| Module                   | Option                     | Default on t640  | Writes firmware state               |
| ------------------------ | -------------------------- | ---------------- | ----------------------------------- |
| `hp-bios.nix`            | `hardware.hpBiosInventory` | enabled          | never                               |
| `hp-bios-boot-order.nix` | `hardware.uefiBootOrder`   | enabled, `check` | only `BootOrder`, only in `enforce` |

There is deliberately **no module for HP setup settings** (AMD-V, "After
Power Loss", Wake-on-LAN, ...). No OS-side backend for them has been verified
on M43 firmware. The kernel driver drops every real setting name. HP's Linux
tool needs ThinPro's own kernel and a proprietary AMI driver. HP's UEFI tool
has not been run on this fleet. Details follow. Until one backend passes the
supervised test below, these settings are set in F10 setup.

## Status summary

| Category                      | Item                                                                                                                                             |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Verified working              | UEFI BootOrder control with `efibootmgr`; T3 kept the OS-set order across one reboot                                                             |
| Verified working (read-only)  | `uefi-boot-order check` on T3 (live) and against T3's copied variables offline; synthetic test matrix on the Mac                                 |
| Verified failure, cause found | `hp-bioscfg` on M43: its hex-string decoder discards the firmware's plain ASCII names; 77 settings collapse into 4 garbage names                 |
| Verified failure, cause found | Sure Start reads (EIO) and boot-time `HWMC` errors: `hp-bioscfg` sends 16+N-byte WMAA buffers; firmware AML reads past them                      |
| Verified firmware defect      | ACPI errors in `\_SB.WMID.WQBD` (string settings) and `WQBE` (ordered lists)                                                                     |
| Verified from firmware image  | `After Power Loss` exists: values `Off` / `On` / `Previous State`, writable, no physical presence; read and set via SW SMI `0xEA7B`              |
| Verified from ThinPro image   | `hptc-bios-cfg` is a bash wrapper; on t640 it runs AMI `LnxBCU` with the proprietary `amifldrv` kernel object (SW SMI and `/dev/mem`)            |
| Verified absent               | No Linux BIOS tool in any M43 SoftPaq; LVFS offers no M43 system firmware                                                                        |
| Documented, untested          | HP `UefiBiosConfig.efi` (in every M43 SoftPaq and in ThinPro) reads/writes settings pre-OS; `hptc-bios-cfg -G/-S` on ThinPro; IGEL HP BIOS Tools |
| Hypothesis                    | A plain-ASCII fallback plus 128-byte WMAA padding in `hp-bioscfg` would expose all 77 enumeration settings, including `After Power Loss`         |
| Hypothesis                    | The v01.22 AMD-V report is a setting reset or a behaviour change, not a removal                                                                  |
| Hardware/firmware limit       | Rollback prevention since v01.05/1.06; SVM is gated by firmware (`MSR_VM_CR`), which the OS cannot override                                      |

## Power-loss recovery ("After Power Loss")

The 12:00 power cut left T3 (and MON1, an S100 and not a t640) off, while T1
came back. On the t640, auto-power-on is decided by the firmware setting below.
No Linux backend can currently read it or set it. Fix it in F10 now on every
t640 that must come back unattended. Do not wait for automation.

**Exact setting, from the M43 v01.12 DSDT** (SP136570, `M43_0112.bin`,
extracted with `uefiextract`, decompiled with `iasl -d`). It is instance 34 of
the 77-entry WMI enumeration table `\_SB.N00A`, served by `WQBC` for GUID
`2D114B49-…`:

```text
Package (0x1C) {
  "After Power Loss", "", "\\System Configuration",
  Zero /* read-only */, One /* shown */, Zero /* physical presence */,
  0x017C, 0x03, " ", " ", " ", Zero,
  "Off" /* current value: static placeholder, overwritten from SMM */,
  0x03, "Off", "On", "Previous State" }
```

- `Off` stays off when power returns. `On` always powers on. `Previous State`
  powers on only if the unit was running. For always-on nodes, `On` is the
  robust choice: with `Previous State`, a node that was already off or
  hung at the time of the cut stays off.
- `"Off"` in the package is the AML's initial value. `WQBC` replaces it with
  the live value from SMM (`WSMI (0xEA7B, Zero, One, <index>, Zero)`, SW SMI
  through port `0xB2`). The shipped default was not observed. Other HP manuals
  give "Power off" as the factory default, which fits T3 staying off.
- Related settings in the same table: `S5 Wake on LAN` (`Disable`/`Enable`),
  `S5 Maximum Power Savings` (`Disable`/`Enable`; enabling it typically cuts
  NIC power in S5 and so kills WoL), `Power on Sunday` … `Power on Saturday`
  (scheduled power-on), and `Remote Wakeup Boot Source`. With S5 WoL working,
  T1 could wake T3 after an outage as a second line of defence. That is
  untested.
- T1 came back, so its setting is probably `On` or `Previous State`. That is
  inferred, not read.

**Per backend, can Linux read or set it?**

| Backend                                     | Read                                                                 | Set                                            | Status                                       |
| ------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------- | -------------------------------------------- |
| `hp-bioscfg` (stock 6.18 / master)          | No: the name decodes to nothing (`-EFAULT`) and the entry is skipped | No                                             | verified (simulation on DSDT; matches sysfs) |
| `hp-bioscfg` + plain-ASCII decode patch     | Plausible: `WQBC` has no AML defect for enumerations                 | Plausible via `WMBA` → `WSMI (0xEA7B, One, …)` | hypothesis; needs a patched module           |
| `UefiBiosConfig.efi` (pre-OS, from SoftPaq) | Documented: `-getconfig -section="After Power Loss"`                 | Documented: `-setconfig=<file>`                | untested                                     |
| `hptc-bios-cfg` → AMI `LnxBCU` (ThinPro)    | Documented (`-G`)                                                    | Documented (`-S`)                              | untested; only usable by booting ThinPro     |
| IGEL HP BIOS Tools                          | Documented (`settings -g`)                                           | Documented (`settings -c`, REPSET file)        | untested; IGEL OS only                       |
| F10 setup                                   | yes                                                                  | yes                                            | the only verified path                       |

### Supervised one-machine test (owner approval required)

Use T3 (never T1, which hosts the router VM), with a monitor and keyboard
attached and someone able to pull the plug. Each step needs explicit approval.
Stop at the first unexpected result.

**Option A: `UefiBiosConfig.efi` from systemd-boot (preferred; HP-signed,
the same mechanism as F10's BCU save/restore).**

1. On the Mac, take `ToolLess/HP/UefiBCU/UefiBiosConfig.efi` from the SoftPaq
   that matches the installed BIOS, or the newest one. Verify the SoftPaq
   SHA-256 against its `.cva`. Copy it to T3's ESP as
   `\EFI\HP\UefiBCU\UefiBiosConfig.efi`.
2. Read only: add a one-shot loader entry
   `/boot/loader/entries/hp-bcu-get.conf`:

   ```text
   title HP BCU get (read-only)
   efi   /EFI/HP/UefiBCU/UefiBiosConfig.efi
   options -getconfig=\EFI\HP\UefiBCU\t3.txt
   ```

   Then run `systemctl reboot --boot-loader-entry=hp-bcu-get.conf`. Back in
   Linux, read `/boot/EFI/HP/UefiBCU/t3.txt`. That file names every setting
   and value as the firmware sees it. It contains machine identifiers
   (serial, MAC, asset tag), so **never commit it**.

3. Write, only after reviewing step 2. Create a file with just the one
   setting, in BCU format (`*` marks the chosen value):

   ```text
   BIOSConfig 1.0
   After Power Loss
   	Off
   	*On
   	Previous State
   ```

   Then use an entry with `options -setconfig=\EFI\HP\UefiBCU\apl.txt` (add
   `-pw=` only if a setup password exists; agenix, not the repo). Re-run step 2
   and diff. Finally, pull power for 10 s with the unit running and confirm it
   comes back.

- Risk: the tool writes setup NVRAM through HP's replicated-setup protocol.
  A malformed file could change other settings. Whether it returns to the boot
  manager or resets is unknown. The read step is the low-risk part.
- Recovery: F10, then File → Apply Factory Defaults (or set the value by hand).
  If the unit won't POST: clear CMOS (battery/jumper), or BootBlock Emergency
  Recovery from a USB key as described in the t640 guide.

**Option B: patched `hp-bioscfg`** (needed anyway for a declarative NixOS
module). Build the module out of tree for the running kernel with the two
changes under "Feasibility". On T3: `modprobe -r hp_bioscfg; insmod ./hp-bioscfg.ko`,
then `cat '/sys/class/firmware-attributes/hp-bioscfg/attributes/After Power Loss/'{current_value,possible_values}`.
Write only after the read works: `echo On > …/current_value`, check
`pending_reboot` = 1, reboot, read back, then do the plug test. Risk: the
earlier T3 hang followed live WMI reads into SMM (cause unknown), so expect
that a hang is possible. Recovery: power-cycle, blacklist the module, then F10.

**Option C: ThinPro live USB + `hptc-bios-cfg -G`.** This runs HP's
supported stack on HP's own kernel. It is not recommended: it boots a
foreign OS, and ThinPro carries `hptc-secureboot` and fwupd, which may
stage dbx/capsule updates. Secure Boot is off on T3 today. If ever used,
pull the NVMe/SSD first and only run `-G`.

## UEFI boot order (`hardware.uefiBootOrder`)

`uefi-boot-order` keeps the installed boot loader first in `BootOrder`. It uses
only standard UEFI variables, so it works whether or not HP's settings
interface does.

- **Target resolution.** It picks the single `Boot####` entry whose device
  path contains a GPT `HD()` node with the ESP's PARTUUID and a file node equal
  to `loader` (default `\EFI\systemd\systemd-bootx64.efi`, compared
  case-insensitively). The ESP's PARTUUID comes from `/proc/self/mountinfo`
  and `/dev/disk/by-partuuid`. Boot numbers are never configured, because
  firmware renumbers entries (T3's Linux entry moved from absent to `0003`, and
  firmware added its own `0009` partition entry).
- **Policy: never move a network-boot entry above Linux Boot Manager.** The
  only change the tool ever makes is moving the target to the front. Every
  other entry keeps its relative order, so the firmware disk entry, USB, and
  IPv4/IPv6 PXE/HTTP stay available as fallbacks below it. The script refuses
  (exit 1) any write that is not "loader first, rest unchanged". If the target
  is missing from `BootOrder`, it is prepended. `BootNext` is reported and
  never cleared.
- **Modes.** `check` exits 0 when compliant and 2 on drift (the systemd unit
  then fails and shows in `systemctl --failed`; a switch that restarts it
  reports the failed unit). `plan` prints the proposed order and exits 0.
  `apply` (used by `mode = "enforce"`) writes only on drift, via
  `efibootmgr --bootorder`, then re-reads `BootOrder` and fails if it doesn't
  match what was written.
- **Default is `check`.** A BootOrder write is an NVRAM write that NixOS
  rollbacks cannot undo. It has been exercised on M43 only once, imperatively,
  and a wrong order can leave a headless node PXE-looping. Enforcement is
  opt-in per host.
- **Skips cleanly** (exit 0, `{"skipped": "not booted via UEFI"}`) when
  `/sys/firmware/efi` is absent.
- **Fails loudly** (exit 1) when booted via UEFI but efivarfs is missing,
  `BootOrder` is unset, no entry or several entries match, the match is
  inactive, the ESP isn't mounted, or the write is rejected or silently
  ignored. It never creates, activates or deletes entries.
- The unit runs with `ProtectSystem=strict` and private networking. The lock
  is `/run/lock/uefi-boot-order.lock`, shared with interactive runs.
- The JSON output contains boot numbers only: no descriptions, MACs or device
  paths.

```sh
uefi-boot-order check        # drift detection, read-only
uefi-boot-order plan         # dry run: show desired order
uefi-boot-order apply        # write only if drifted (needs approval per host)
systemctl status uefi-boot-order
```

To enforce on a host after owner approval:

```nix
hardware.uefiBootOrder.mode = "enforce";
```

`enforce` asserts `boot.loader.efi.canTouchEfiVariables`. The unit runs once
per boot (and on switches that change it), after the ESP is mounted.

### Validation performed (read-only)

On T3, in an earlier session, the script was streamed to the existing store
Python and run in `check` mode against live efivarfs, with automatic ESP
detection:

```text
{"mode": "check", "target": "0003", "boot_order": "0003,0009,0001,0002,0004,0005,0006,0007,0008",
 "desired_boot_order": "0003,0009,0001,0002,0004,0005,0006,0007,0008", "compliant": true,
 "boot_next": null, "wrote": false}
exit=0
```

T3's sanitized entries (`efibootmgr -v` from `nix shell nixpkgs#efibootmgr`,
v18; MACs, partition GUIDs and the disk serial redacted):

| Entry | Description (class)                         | Device path shape                                 |
| ----- | ------------------------------------------- | ------------------------------------------------- |
| 0003  | Linux Boot Manager                          | `HD(<part>)/\EFI\systemd\systemd-bootx64.efi`     |
| 0009  | firmware-created "UEFI: SSD …, Partition 1" | `PciRoot/…/NVMe(<redacted>)/HD(<part>)` (no file) |
| 0001  | USB Floppy/CD                               | AMI `VenMedia`                                    |
| 0002  | USB Hard Drive                              | AMI `VenMedia`                                    |
| 0004  | IPv4 (TFTP) PXE                             | `…/MAC(<mac>)/IPv4(DHCP)`                         |
| 0005  | IPv6 (TFTP) PXE                             | `…/MAC(<mac>)/IPv6`                               |
| 0006  | IPv4 (HTTP)                                 | `…/MAC(<mac>)/IPv4(DHCP)/Uri()`                   |
| 0007  | IPv6 (HTTP)                                 | `…/MAC(<mac>)/IPv6/Uri()`                         |
| 0008  | inactive "Fake Legacy Option"               | AMI `VenMedia`                                    |

`BootCurrent=0003`, `Timeout=0`, Secure Boot disabled (`SecureBoot` = 0),
systemd-boot 260.2. The former Windows Boot Manager entry (`0000`) is gone.

Offline cases (T3's copied variables, and synthetic variables on the Mac with
an `efibootmgr` double that writes only the scratch copy):

| Case                                       | Result                                             |
| ------------------------------------------ | -------------------------------------------------- |
| Live copy, `check` / `apply`               | compliant, exit 0, no write attempted              |
| Linux moved behind the network entries     | `check` exit 2; `plan` shows Linux first, exit 0   |
| `apply` on that drift                      | one write, re-read verified, then `check` exit 0   |
| Target absent from `BootOrder`             | prepended                                          |
| Wrong ESP PARTUUID / duplicate / inactive  | exit 1 with the reason                             |
| `BootNext` present                         | warning, reported, untouched                       |
| No `/sys/firmware/efi` (legacy boot)       | skipped, exit 0                                    |
| UEFI boot but no efivarfs; no `BootOrder`  | exit 1                                             |
| Writer exits 0 but changes nothing / fails | exit 1 ("BootOrder is … after writing …") / exit 1 |

The `apply` path has not been run against real firmware. The equivalent
`efibootmgr --bootorder` write was run imperatively on T3 before this work, and
the firmware kept that order across a reboot. That is one reboot on one
machine. It does not prove persistence across firmware resets, "Apply
Defaults", or disk changes; the per-boot `check` exists to catch those cases.

## Why `hp-bioscfg` fails on M43 (root cause)

The firmware exposes the full HP WMI BIOS interface. On T3 (read-only
`/sys/bus/wmi/devices/*/{object_id,instance_count}`):

| GUID (role in `hp-bioscfg`)       | ACPI object | Instances       |
| --------------------------------- | ----------- | --------------- |
| `2D114B49-…` enumeration          | `WQBC`      | 77              |
| `988D08E3-…` string               | `WQBD`      | 44              |
| `14EA9746-…` ordered list         | `WQBE`      | 2               |
| `8232DE3D-…` integer              | `WQBG`      | 1               |
| `322F2028-…` password             | `WQBF`      | 1               |
| `1F4C91EB-…` set-setting method   | `WMBA`      | 1               |
| `5FB7F034-…` BIOS method (`WMAA`) | `WMAA`      | 1 (bound twice) |

### 1. Names: a driver decoding bug triggered by firmware encoding

`\_SB.N00A` holds the 77 enumeration settings as static packages whose
strings are plain ASCII (see `After Power Loss` above). `WQBC` fills the
current value from SMM and returns the package. The element layout matches
what `hp-bioscfg` expects. But `hp_init_bios_package_attribute()` sends every
name through `hp_convert_hexstr_to_str()` (`bioscfg.c`), which assumes HP's
newer encoding: each character as a five-byte `"0xNN "` token. It copies each
5-byte window into `char tmp[5]` (4 characters), runs `kstrtol(tmp, 16)`, and
keeps any window that happens to parse as hex. Simulating that on the 77
names in the v01.12 DSDT (re-run in this session; the same result as the
earlier run on T3's live DSDT):

```text
instances 77
After Power Loss index 34 -> None
converted 6 Counter({'\x0e': 3, 'Þ': 1, '\x12': 1, 'ú': 1})
'Setup Browse Mode' -> 'Þ'            # window "de"
'Password Prompt on F9 & F12' -> '\x12'
'Default Setup' -> 'ú'
'BIOS Update' -> '\x0e'               # trailing "e"
'UMA Frame Buffer Size' -> '\x0e'     (x2)
```

These are exactly the four directories on T1/T3 and in kernel bug 222277
(`\336`, `\022`, `\372`, `\016`). The other 71 names, `After Power Loss` and
`Virtualization Technology (VTx/VTd)` among them, return `-EFAULT` and are
skipped. Duplicates are dropped by `kset_find_obj()`. Strings never get that
far, because `WQBD` aborts in AML (`CreateField` of length zero). Ordered
lists fail in `WQBE` (index `0x50` past a `0x50`-byte buffer). Those two are
genuine firmware AML defects.

### 2. Sure Start EIO and `HWMC` buffer-limit errors: undersized WMAA input

`hp-bioscfg`'s `hp_wmi_perform_query()` (`biosattr-interface.c`) allocates
`struct_size(args, data, insize)`: a 16-byte `SECU` header plus exactly
`insize` bytes. The sibling `hp-wmi` driver pads every call to
`max(insize, 128)` bytes. Firmware `HWMC` reads input fields past the
declared size:

| Caller                                 | `insize` | Buffer       | Logged error                                                                                    |
| -------------------------------------- | -------- | ------------ | ----------------------------------------------------------------------------------------------- |
| SPM `GET_STATE` at probe               | 0        | 16 B = 128 b | `Field [D008] at bit offset/length 128/8 exceeds size of target Buffer (128 bits)` (bug 222277) |
| Sure Start `GET_LOG_COUNT` / `GET_LOG` | 1        | 17 B = 136 b | `Field [D009] at bit offset/length 136/8 exceeds size of target Buffer (136 bits)` (T3)         |

The buffer sizes match the error offsets exactly. That makes this a driver
call ABI mismatch that `hp-wmi` already works around, not a missing
interface. HP error `0x300a` follows from the aborted method. The
"cannot be instantiated multiple times" warning comes from the firmware
declaring `5FB7F034-…` twice.

### Corroboration and upstream state

[Kernel bug 222277](https://bugzilla.kernel.org/show_bug.cgi?id=222277) ("hp-bioscfg:
HP t640 Thin Client: BIOS settings not enumerated", NEW, opened 2026-11-16 by
an unrelated reporter, read via the Bugzilla REST API) shows the same six
entries and the same AML errors on M43 **v01.24 (04/28/2026)** and v01.08,
Fedora kernel 7.3.3. An earlier session's DSDT extractions from v01.12, v01.21,
v01.22, v01.23 and v01.24 all reproduce the same four names. **No BIOS update
fixes this.**

Upstream `master` (checked 2026-11-18) still decodes names only as hex
strings and does not pad WMAA input. The 2026 series fixes package-length
handling and memory safety, not the encoding: `40e10e6cc8f7` "accept reduced
ACPI packages from older HP BIOS", `b0e2af3ec94e`, `05c808362e80`,
`cb6b1b0fb236`, and `6a6f3051e705`/`a97dd0e1e49a` (OOB write and zeroing in
`hp_convert_hexstr_to_str()`). Current tip: v7.4 merge `c339f4010dea`.

### Feasibility

- **Upstream patch: feasible and small, in two parts.** (1) In
  `hp_convert_hexstr_to_str()` (or its callers), detect input that is not
  `"0xNN "`-tokenised and copy it as plain ASCII. (2) Pad the WMAA input
  buffer to at least 128 bytes, as `hp-wmi` does. Part 1 would expose the 77
  enumeration settings through the standard firmware-attributes ABI (fwupd's
  `bios-settings.d` policies would follow). Part 2 should fix Sure Start and
  the probe-time `HWMC` error. Setting goes through `1F4C91EB-…`/`WMBA`,
  which ends in `WSMI (0xEA7B, One, …)`. String and ordered-list settings
  (including the firmware boot order) stay broken by the firmware's AML.
  Neither part has been built or run.
- **Userspace reader: not feasible.** Current values come from SMM through
  ACPI method evaluation. Linux offers no userspace path to evaluate WMI data
  blocks: `CONFIG_ACPI_DEBUGGER` is off, `acpi_call` is out of tree, and
  `/dev/mem` is `STRICT_DEVMEM`. The static DSDT gives names and possible
  values only, never the current value.

## Reproducible driver candidate (2026-11-20)

`pkgs/custom/hp-bioscfg-m43/` now contains an experimental external-module
package and a reviewable GPL kernel patch. It builds against the selected
host kernel's source and development output, so its vermagic follows that
kernel. The patch was applied without fuzz to Linux v6.18.38 source and
fixture-tested locally; **the complete kernel module has not been built or
loaded**. A different kernel source may reject the patch; do not force it.

The decoder accepts bounded plain ASCII and strictly formed `0xNN` tokens,
preserves escaping for backslash and whitespace, and rejects malformed tokens,
embedded NULs and non-ASCII bytes. A terminal encoded NUL remains supported.
Its zeroed allocation also avoids the short-token allocation problem in the
6.18 decoder. The WMAA change allocates a 16-byte header plus at least 128
zeroed payload bytes, retaining the real `datasize` and copying only that many
input bytes. It does not change the set-setting method. String/ordered-list
AML defects and duplicate WMI GUIDs remain outside this patch.

Current upstream was rechecked at
[`8dac6df92a2e66e2098bbc69061964cfe7e8375b`](https://github.com/torvalds/linux/tree/8dac6df92a2e66e2098bbc69061964cfe7e8375b/drivers/platform/x86/hp/hp-bioscfg):
the decoder still assumes hex tokens and WMAA still allocates only `insize`
payload bytes. The earlier conclusions about those defects still apply.

`hardware.hpBiosInventory.candidateDriver` is a build target only. It does
not add an external module to the boot environment, install a service, or
change the existing inventory or standard UEFI boot-order module. For an
approved build on T2 (maximum two jobs and two cores), or on a native GitHub
runner with the usual private-input overrides:

```sh
nix build --no-link --max-jobs 2 --cores 2 \
  .#nixosConfigurations.T3.config.hardware.hpBiosInventory.candidateDriver
```

The package runs `test_patch.py` during `postPatch`. That script extracts the
**patched C decoder and query-buffer setup**, compiles them with a small
userspace allocation shim, then checks plain names (including `After Power
Loss`), bounded non-NUL-terminated input, tokenised names, escaping, malformed
input, and every payload length from 0 through 256. It checks the actual
allocated length, header, original `datasize`, copied bytes and zero padding.
It accesses no firmware. These fixtures pass on macOS with `cc`; they do not
prove ACPI/SMM compatibility or a successful kernel-module build.

```sh
# Offline, after applying m43.patch to a scratch Linux source tree:
python3 pkgs/custom/hp-bioscfg-m43/test_patch.py /path/to/patched/linux
```

Safe live evidence collected on T3 on 2026-11-20: kernel 6.18.38, M43 v01.11,
the same four malformed directory names plus `Sure_Start`/`pending_reboot`,
and existing boot-log WQBD/WQBE/HWMC/WMAA errors. Only cached identity files,
directory listings and existing logs were inspected. No vendor attribute was
read and no module was inserted. The later cable diagnosis explains network
outages but does not establish that future SMM queries cannot hang.

**Next parent coordination:** first request the package-only build above;
this does not authorize installation. After successful build and module
metadata review, request a separate T3 console-supervised replacement of the
stock module and one enumeration-only `current_value` read for `After Power
Loss`. Loading the driver executes firmware queries during probe, even before
that read. A hang may require a separately authorized power cycle. Keep
`Sure_Start` reads, writes, reboots, EFI boot and T1 out of that test. No
firmware-setting policy is activated by this implementation.

## HP and IGEL vendor tools

### `hptc-bios-cfg` (HP ThinPro): analysed from the official image

Source: `https://ftp.hp.com/pub/tcdebian/OSImages/T8X72014.dd.gz` (ThinPro
7.2.0, t640 listed in `T8X72014.txt`; 1 214 406 286 bytes, SHA-256
`d1deb9b965aa7a60bd0121d50af0216dd920cf78079990cc938e9d4348dbbab2`). It
was unpacked on the Mac: GPT with `BOOT` (ESP) and `ROOT` (btrfs, zlib
extents). Files were read with a small read-only btrfs leaf scanner; nothing
was executed.

- Package `hptc-bios-cfg` 5.13-5.6.8+hp16 (`amd64`, `Section: non-free/HP`).
  Depends on `linux-image-5.6.8+hp (= 5.6.8+hp16)`, `hptc-secureboot`,
  `fwupd`, `efivar`, `efibootmgr`, `cabextract`, `xmlstarlet`.
- `/usr/sbin/hptc-bios-cfg` is a **bash script** ("v2.00"). It detects the
  model with `hptc-hwsw-id --hw` and dispatches. For `t640` it calls
  `lnxbcu()`: it copies
  `/lib/modules/$(uname -r)/kernel/drivers/misc/amifldrv_mod_LnxBCU.o` to
  `./amifldrv_mod.o` and runs `/usr/sbin/LnxBCU /Get:<tmp>` (or `/Set:`,
  converting the file to UTF-16LE with CRLF), plus `/cspwdfile:` and
  `/nspwdfile:`. `-G` output defaults to `CPQSETUP.TXT`. Sudoers lets users
  run `-G` only.
- `LnxBCU`: ELF x86-64, dynamic (`libstdc++.so.6`, `libcrypto.so.1.0.0`,
  `libm`, `libc`, `libgcc_s`), GCC 4.5.1, with the banner "AMI BIOS
  Configuration Utility". Its strings show: it `insmod`s `amifldrv_mod` and
  `mknod`s `/dev/amifl`; it auto-builds the driver from an embedded
  `amiwrap.c` plus a shipped `amifldrv.o` via `make -C /lib/modules/…/build
SUBDIRS=…` ("Linux does not support Auto Build Driver when Secure Boot
  Enable"); it uses `gSmiPort`/`gAcpiSmiPort` with an SMI mailbox
  (`gSmiMailBox`); it opens `/dev/mem`; it reads `/sys/firmware/efi/systab`
  and efivars; and it toggles `/proc/sys/kernel/nmi_watchdog`.
- `amifldrv_mod_LnxBCU.o`: `license=Proprietary`, "AMI Flash Update utility
  driver", `vermagic=5.6.8+hp`. Symbols: a char device with an ioctl
  (commands `0x4160`–`0x4166`) that allocates kernel buffers (up to 128 KiB),
  `remap_pfn_range` mmap to user space, and `PortWriteByte`, which loads
  user-supplied register values and executes `outb` to a user-chosen port (a
  raw software-SMI trampoline).
- **Interface verdict:** completely different from `hp-bioscfg`. It bypasses
  ACPI/WMI (`WQBC`/`WMBA`/`WMAA`) and talks to an SMM handler directly, with
  physically contiguous buffers and an I/O-port SMI. It plausibly works where
  the WMI path is broken, but that is unverified.
- ThinPro also ships `UefiBiosConfig-1.08-Signed/UefiBiosConfig.efi`. For the
  t640, `hptc-bios-flash` stages it in `\EFI\HP\UefiBCU\` together with
  `HPBU_3.9.0.0` (HpBiosUpdate) for the "tool-less" flash path (image placed
  in `\EFI\HP\BIOS\New`). The firmware applies it on reboot only when the
  setup setting `BIOS Update` allows it.
- **Licence:** `/usr/share/doc/hptc-bios-cfg/copyright` points to the HP
  standard license (`HP-standard-license-15-11`, EULA 826659): "You do not have
  the right to distribute the Software Product"; clause 6 forbids reverse
  engineering or disassembly except as permitted by law. This analysis used
  file metadata, strings, symbol tables and one short disassembly of the
  driver's port-write routine. Do not go further than that.
- **Not packaged, on purpose.** (1) The licence bars redistribution, and this
  repo's CI pushes build outputs to a public Cachix cache. (2) The only
  official source is a 1.2 GB disk image with a btrfs root. (3) The real
  backend is a proprietary kernel object built for `5.6.8+hp`. Using it on
  6.18 means rebuilding and patching AMI's glue around a binary blob,
  disabling lockdown-style protections, and handing a userspace tool
  arbitrary port I/O. That is a worse risk than the patched in-tree driver.

### IGEL HP BIOS Tools (public docs only)

[IGEL's app](https://kb.igel.com/en/igel-apps/current/hp-bios-tools) supports the
t640 ("legacy HP update method only; LVFS is not supported"). Settings are
handled with a BCU/REPSET-format file: `callBiosTools settings -g` exports
`bios_settings<unit_id>`, the file is edited with HP's BCU conventions, and
`settings -c` applies it. Passwords use HPQPswd `.bin` files made on Windows.
Changes apply on reboot. Installing it pulls "Optional Kernel Modules for IGEL
OS 12", which suggests a vendor kernel module like ThinPro's. The binaries
ship only inside IGEL OS, so they were not obtained. Their mechanism is
inferred, not verified.

### `UefiBiosConfig.efi` (UEFI BCU), in every M43 SoftPaq

Path: `ToolLess/HP/UefiBCU/UefiBiosConfig.efi` (PE32+ EFI application,
x86-64). Strings:

```text
Usage: UefiBiosConfig.efi [-h] [-v] [ -getconfig | -getconfig=<filename> [-ascii]
       [-section=<section> [-section=<section> ...]] | -setconfig=<filename> [-pw=<password>] ]
UefiBiosConfig.efi -getconfig=file1 -section="VGA Boot Device" -section="Processor.*"
```

It uses the firmware's `HP_REPLICATED_SETUP_INTERFACE(2)_PROTOCOL`, a
boot-services protocol, so it works only before `ExitBootServices`. It takes
its arguments from UEFI LoadOptions, which systemd-boot's `options` line
provides. This is the most credible backend for a future declarative module:
a NixOS-managed loader entry runs `-getconfig=` to capture state into the
ESP, Linux diffs that against a desired file, and an approved `-setconfig=`
one-shot applies it. It has **not been run**.

## Firmware (SoftPaqs)

Metadata was re-fetched on 2026-11-18 from each SoftPaq's `.html` and `.cva` on
`ftp.hp.com`. SP136570 was downloaded again (SHA-256 matches the CVA). The
earlier session downloaded all six, matched their hashes, and unpacked them
with `7zz x`.

| SoftPaq  | Version  | Effective  | Supersedes | Purpose  | Release notes                                                                                                   |
| -------- | -------- | ---------- | ---------- | -------- | --------------------------------------------------------------------------------------------------------------- |
| SP136570 | 00.01.12 | 2021-12-31 | SP136008   | Critical | CVE-2021-39297, CVE-2021-39301                                                                                  |
| SP143954 | 00.01.16 | 2023-01-31 | SP141831   | Routine  | "Enhance security vulnerabilities" (no CVEs listed)                                                             |
| SP152017 | 00.01.21 | 2024-05-12 | SP150609   | Critical | CVE-2023-39538, CVE-2023-39539, CVE-2023-45229 … 45237 (PixieFail)                                              |
| SP161544 | 00.01.22 | 2025-08-30 | SP152017   | Routine  | CVE-2024-0179, CVE-2024-21925; CVE-2023-31315 (AMD SMM lock, "Sinkclose")                                       |
| SP170067 | 00.01.23 | 2026-03-20 | SP161544   | Routine  | Pass 2. Updates the Microsoft Secure Boot CA. CVA `VendorVersion=M42_0123A2` is a typo; the image is M43 v01.23 |
| SP173784 | 00.01.24 | 2026-07-17 | SP170067   | Routine  | CVE-2021-26381, CVE-2021-26410, CVE-2024-36355                                                                  |

Every page lists HP ThinPro, ThinPro Zero and Windows 10 IoT. SP136570 and
SP143954 also document the Linux flash path (`hptc-bios-flash BIOS.bin` on
ThinPro, `ami-flash BIOS.bin` elsewhere). The supersede chain shows
intermediate releases not covered here (SP141831, SP150609, between v01.12 and
v01.21).

- **v01.22 AMD-V report.** An [HP Community thread](https://h30434.www3.hp.com/t5/Business-PCs-Workstations-and-Point-of-Sale-Systems/HP-t640-BIOS-M43-v01-22-disabled-SVM-AMD-V-Need-link-to/td-p/9566567)
  (marked solved; the page itself is blocked by Cloudflare, so this comes from
  the search snippet) reports that after 00.01.22 setup no longer offers SVM
  and Proxmox reports "SVM disabled by BIOS". The user asked for a 00.01.18 or
  00.01.20 SoftPaq to downgrade. No HP statement was found. Evidence from the
  images: the WMI enumeration `Virtualization Technology (VTx/VTd)` is
  byte-identical in the v01.21, v01.22 and v01.24 DSDTs, the setting list is
  unchanged from v01.21 to v01.24, and the UTF-16 `SVM Mode` /
  `Virtualization Technology` setup strings are present in every image.
  **Removal is not supported by the evidence.** The likeliest explanations,
  all untested: the flash reset the setting to its `Disable` default (the
  DSDT's initial value is `Disable`); the option was hidden from the F10 form
  (form visibility is not in the DSDT, so a hidden-but-present setting fits
  the evidence); or the CVE-2023-31315 SMM-lock fix changed behaviour.
- **"Original v01.24 shipped the wrong firmware."** Not found in any source
  consulted. The SP173784 currently served is consistent: M43 v01.24
  strings, capsule `FirmwareVersion=0x00010018`, hashes match the CVA. Its
  CVA is stamped 2026-07-22, after the 2026-07-17 effective date, which could
  mean a replacement upload. Bug 222277 reports v01.24 with BIOS date
  04/28/2026. Unverified.
- **Rollback.** The M43 history adds "BIOS rollback prevention" (v1.05, v1.06)
  and fixes rollback to M42/M43_0102 with MPM locked or unlocked (v1.03,
  v1.04). No rollback setting is exposed over WMI. Assume downgrades below a
  firmware-enforced floor are refused. AMD PSP security-patch-level
  anti-rollback after the 2024–2026 AGESA CVE fixes is likely but unverified.
  IGEL exposes an "Allow to flash older version (USE AT YOUR OWN RISK)" switch,
  so HP's updater can attempt downgrades. Recovery options: F10 Apply Defaults;
  CMOS clear; BootBlock Emergency Recovery from a FAT32 USB key carrying the
  `\HP\BIOS\New` layout (as in the SoftPaq `ToolLess` folder), as documented
  in HP's t640 guide. Do not plan on downgrading to recover AMD-V.
- **LVFS.** fwupd offers only dbx on these hosts. IGEL also lists the t640 as
  LVFS-unsupported.
- **OS-side flash tools:** none in any SoftPaq. ThinPro's `hptc-bios-flash`
  stages a tool-less update on the ESP. Flashing stays out of scope; nothing
  was flashed.

## Read-only commands run

### This session (2026-11-18, Mac only; no home-lab access)

```sh
curl -O https://ftp.hp.com/pub/tcdebian/OSImages/T8X72014.dd.gz   # ThinPro 7.2
gunzip -c T8X72014.dd.gz > T8X72014.dd; sgdisk -p T8X72014.dd
dd if=T8X72014.dd of=root.part bs=512 skip=512000 count=7488463   # btrfs ROOT
python3 -I btrfs_extract.py root.part out/ hptc-bios-cfg LnxBCU amifldrv_mod_LnxBCU.o ...
file / strings / llvm-nm / llvm-readelf -p .modinfo   # on the extracted files
curl -O https://ftp.hp.com/pub/softpaq/sp136501-137000/sp136570.exe; 7zz x sp136570.exe
uefiextract M43_0112.bin all; iasl -d DSDT.aml        # nixpkgs#uefitool, #acpica-tools
curl https://bugzilla.kernel.org/rest/bug/222277/comment
curl https://raw.githubusercontent.com/torvalds/linux/master/drivers/platform/x86/hp/{hp-bioscfg/*.c,hp-wmi.c}
```

Downloads and extractions stay in scratch space. They were never committed.

### Earlier session on T3 (2026-11-18)

All over SSH as root. No module loads, no sysfs/efivar writes, no `/dev/mem`
access, no reboots. `nix shell` added efibootmgr to `/nix/store`.

```sh
dmesg | grep -iE "hp|wmi|bioscfg|svm"
for d in /sys/bus/wmi/devices/*; do cat $d/object_id $d/instance_count; done
ls -la /sys/class/firmware-attributes/hp-bioscfg/attributes/ | cat -v
cat /sys/class/firmware-attributes/hp-bioscfg/attributes/Sure_Start/*   # both: EIO
cat /sys/firmware/acpi/tables/{DSDT,SSDT1..7}
zcat /proc/config.gz | grep -E "ACPI_DEBUGGER|STRICT_DEVMEM|HP_BIOSCFG"
bootctl status
nix shell nixpkgs#efibootmgr -c efibootmgr -v
python3 -I - check --loader '\EFI\systemd\systemd-bootx64.efi' --esp /boot < uefi-boot-order.py
```

Sanitized dmesg (v01.11, kernel 6.18.38):

```text
SVM disabled (by BIOS) in MSR_VM_CR
hp-bioscfg 5FB7F034-…-10: Legacy driver hp-bioscfg cannot be instantiated multiple times
ACPI Error: Aborting method \_SB.WMID.WQBD due to previous error (AE_AML_OPERAND_VALUE)
ACPI Error: Aborting method \_SB.WMID.WQBE due to previous error (AE_AML_BUFFER_LIMIT)
ACPI BIOS Error (bug): AE_AML_BUFFER_LIMIT, Field [D009] at bit offset/length 136/8 exceeds size of target Buffer (136 bits)
ACPI Error: Aborting method \_SB.WMID.WMAA due to previous error (AE_AML_BUFFER_LIMIT)
hp_bioscfg: Returned error 0x300a, "Generic/Other error"
```

**Incident note:** T3 stopped responding at some point after that read-only
session, and the cause is undiagnosed. The only firmware-executing calls were
the `Sure_Start` audit-log reads (live WMI queries into SMM, which returned
EIO) and UEFI runtime `GetVariable` reads via efivarfs. Until the cause is
known, treat even read-only WMI attribute reads on M43 as non-trivial. The
inventory command deliberately reads only `pending_reboot` and directory names.

### Earlier findings (2026-11-17)

T1 and T3 both run M43 v01.11 (09/13/2021) on 6.18.38 with `hp_bioscfg` and
`hp_wmi` loaded, the same six-entry attribute layout, and
`pending_reboot = 0`. fwupd 2.1.5's BIOS-settings JSON on T1 contains raw
control characters (the same garbage names). AMD-V is on for T1 (set manually
in F10: `kvm_amd` loaded, `/dev/kvm` present) and off for T3. On T3's PXE
session, before install, BootOrder held Windows, USB and network entries and
no Linux entry. After the NixOS install, Linux Boot Manager was registered
behind the network entries and moved first with `efibootmgr`; T3 then booted
from NVMe. T2 has not been inspected.

## Inventory (`hardware.hpBiosInventory`)

`sudo hp-bios-inventory` prints JSON. It counts HP attributes and malformed
names, reports the BIOS version/date and KVM indicators, and classifies
BootOrder entries without printing descriptions or device paths. It exits
non-zero on read errors and has no write path. It cannot report
`After Power Loss` (see above).

## Gate for HP setting enforcement

1. Choose a backend: a patched `hp-bioscfg` (plain-ASCII decode and 128-byte
   WMAA padding), or `UefiBiosConfig.efi` run pre-OS from a systemd-boot entry.
2. On T3 (never T1), with console access, capture the real names and values
   read-only (the supervised test above).
3. Only then add a desired-settings option. It must be limited to verified
   names and values, separate from boot order, and support dry-run, drift
   detection, `pending_reboot` handling, and no write when compliant. Keep
   passwords in agenix runtime files. The first candidates are
   `After Power Loss = On` and `S5 Wake on LAN = Enable`.
4. Test one change with an approved reboot and a plug-pull, verify that it
   persists, then roll out. T1's AMD-V must never be touched by automation;
   T1 hosts the router VM.

## Sources

- Linux `hp-bioscfg` [master](https://github.com/torvalds/linux/tree/master/drivers/platform/x86/hp/hp-bioscfg)
  (`bioscfg.c` `hp_convert_hexstr_to_str()`, `biosattr-interface.c`
  `hp_wmi_perform_query()`, `surestart-attributes.c`) and
  [`hp-wmi.c`](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/hp/hp-wmi.c)
  (`actual_insize = max(insize, 128)`);
  [firmware-attributes ABI](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-class-firmware-attributes)
- [Kernel bug 222277](https://bugzilla.kernel.org/show_bug.cgi?id=222277)
- HP SoftPaqs [SP136570](https://ftp.hp.com/pub/softpaq/sp136501-137000/sp136570.html),
  [SP143954](https://ftp.hp.com/pub/softpaq/sp143501-144000/sp143954.html),
  [SP152017](https://ftp.hp.com/pub/softpaq/sp152001-152500/sp152017.html),
  [SP161544](https://ftp.hp.com/pub/softpaq/sp161501-162000/sp161544.html),
  [SP170067](https://ftp.hp.com/pub/softpaq/sp170001-170500/sp170067.html),
  [SP173784](https://ftp.hp.com/pub/softpaq/sp173501-174000/sp173784.html)
  (and their `.cva` files and `History.htm`)
- HP ThinPro 7.2.0 image [T8X72014](https://ftp.hp.com/pub/tcdebian/OSImages/T8X72014.txt)
- [HP Community: v01.22 disabled SVM](https://h30434.www3.hp.com/t5/Business-PCs-Workstations-and-Point-of-Sale-Systems/HP-t640-BIOS-M43-v01-22-disabled-SVM-AMD-V-Need-link-to/td-p/9566567);
  [HP Community: hptc-bios-cfg BIOS update flow](https://h30434.www3.hp.com/t5/Desktop-Operating-Systems-and-Recovery/How-do-you-update-the-BIOS-on-a-thin-client/m-p/9130725)
- [IGEL HP BIOS Tools](https://kb.igel.com/en/igel-apps/current/hp-bios-tools);
  [HP BCU guide](https://ftp.hp.com/pub/caps-softpaq/cmit/whitepapers/BIOS_Configuration_Utility_User_Guide.pdf);
  [fwupd BIOS settings](https://github.com/fwupd/fwupd/blob/main/docs/bios-settings.md)
