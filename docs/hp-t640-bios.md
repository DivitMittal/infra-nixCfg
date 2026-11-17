# HP t640 BIOS inventory and configuration

The t640 profile imports `hosts/nixos/_homelab/hp-bios.nix` and enables
`hardware.hpBiosInventory.enable` by default. It loads `hp-bioscfg` and installs
`hp-bios-inventory`. Run as root on each machine:

```sh
sudo hp-bios-inventory
```

Disable it with `hardware.hpBiosInventory.enable = false;`. To use it in another
NixOS profile, import that module and enable the option. It requires Linux,
Python 3 (supplied by the module), and readable sysfs; UEFI inventory additionally
requires mounted efivarfs. Missing interfaces produce null/empty results;
permission, malformed EFI payload, and other read errors produce a sanitized
error list and nonzero exit status.

The command emits JSON to stdout only. It counts HP attributes without dumping
names or arbitrary values, reports BIOS version/date and KVM indicators, and
classifies BootOrder entries without printing descriptions or device paths.
There is no activation script, background service, automatic enforcement,
firmware update, reboot, or fwupd dependency. No BIOS credentials enter the Nix
store. This module deliberately has no desired-settings option until the actual
t640 interface is verified.

## Findings on T1

Read-only checks on 2026-11-17 found:

| Observation           | Result                                                                                                                           |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Running kernel        | 6.18.38                                                                                                                          |
| Firmware              | M43 v01.11, dated 09/13/2021                                                                                                     |
| HP modules            | `hp_bioscfg` and `hp_wmi` loaded                                                                                                 |
| HP attribute root     | Six entries: `Sure_Start`, `pending_reboot`, four malformed names                                                                |
| Driver reboot flag    | `0`                                                                                                                              |
| fwupd                 | 2.1.5                                                                                                                            |
| fwupd BIOS query      | Five entries, no usable virtualization or boot-order setting; JSON contains raw control characters and fails strict JSON parsing |
| AMD virtualization    | `kvm_amd` loaded, `/dev/kvm` present, kernel reports nested virtualization and nested paging enabled                             |
| Installed boot loader | `bootctl status` identifies systemd-boot 260.2 and a Linux Boot Manager entry                                                    |

The kernel also logs a duplicate-instantiation warning for `hp-bioscfg` and a
`0x300a` generic error. These observations do not establish the root cause.
`Sure_Start` is not evidence of a usable virtualization/boot-order interface.
No BIOS setting was changed. T2/T3 were not inspected; do not extrapolate T1's
firmware or settings to the fleet.

AMD-V is already operational on T1. The inventory's CPU flag, loaded-module,
and device fields are indicators, not a VM execution test. Loading `kvm-amd`
does not enable virtualization in firmware when firmware has disabled it.

Linux Boot Manager's existence does not establish its priority over PXE. The
inventory reads UEFI BootOrder and classifies active entries by description.
`linux_before_network_by_label` is null unless both recognizable Linux and
network entries exist and there are no unknown entries. Classification is a
heuristic: firmware can use different labels, BootNext can override a boot, and
HP's own boot policy may differ. The command does not publish BootNext or EFI
device paths. Review boot order privately at the console before changing it;
boot identifiers must be discovered separately on each machine.

## What upstream supports

The [Linux firmware-attributes ABI](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-class-firmware-attributes)
defines settings, allowed values, current values, and HP ordered lists.
[`hp-bioscfg`](https://github.com/torvalds/linux/tree/master/drivers/platform/x86/hp/hp-bioscfg)
is the relevant settings driver.
[`hp-wmi`](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/hp/hp-wmi.c)
primarily exposes platform features such as hotkeys, radio state and thermal
profiles; its presence supplies no generic BIOS configuration interface.

There are upstream fixes for shortened ACPI packages, including
[accept reduced packages](https://github.com/torvalds/linux/commit/40e10e6cc8f7)
and the associated
[review discussion](https://lore.kernel.org/platform-driver-x86/20260704160759.236249-1-meatuni001@gmail.com/).
Reviewers also discuss WMI data marshaling and buffer sizing. The reported
hardware was an EliteBook; that does not demonstrate that these changes fix the
t640's malformed names. No patched kernel was built or booted for this work,
and inclusion/backport status in T1's kernel has not been established. A newer
kernel is a coordinated diagnostic experiment, not a proven remedy.

The [fwupd BIOS settings documentation](https://github.com/fwupd/fwupd/blob/main/docs/bios-settings.md)
provides `fwupdmgr get-bios-setting --json`, interactive setting changes, and a
real declarative policy directory: `/etc/fwupd/bios-settings.d/*.json`. Policies
use the documented BIOS-settings JSON representation and are applied on daemon
startup. They depend on correctly exposed kernel attributes; fwupd cannot
recover missing settings just by declaring a policy. Its HP plugin is not an
independent replacement for the kernel interface. Do not generate policy from
T1's malformed inventory. Policy files are intentionally absent from this
module.

HP's [BCU user guide](https://ftp.hp.com/pub/caps-softpaq/cmit/whitepapers/BIOS_Configuration_Utility_User_Guide.pdf)
describes Windows/WinPE and the HP InstrumentedBIOS WMI namespace. It is a
possible separately coordinated provisioning path, not a demonstrated native
NixOS backend. The [HP thin-client guide](https://h10032.www1.hp.com/ctg/Manual/c06595882.pdf)
also documents F10 setup and BCU. Neither establishes a working Linux tool for
this particular firmware. Firmware flashing and BIOS setting changes are
separate operations; LVFS firmware availability alone proves neither settings
support nor a fix for enumeration.

## Gate for future enforcement

Before adding a writer, coordinate console/recovery access and any kernel or
firmware experiment with the fleet owner. Re-run inventory on each machine,
verify that setting names are legible, and privately inspect the relevant
`type`, `is_readonly`, `current_value`, `possible_values` and authentication or
physical-presence requirements. Capture the exact advertised name/value for
AMD virtualization and the actual boot-order representation. Avoid guessed
names or values such as `AMD-V=Enabled`.

Only then test an explicit opt-in change on one machine, with an independently
approved reboot if needed, and verify persistence and the next boot before
fleet rollout. Keep credentials in agenix/runtime files, never Nix strings.
Preserve PXE as a recovery option while placing the installed Linux entry first.
Do not implement retry/reboot loops when a setting is absent or rejected.
Until those gates pass, use coordinated F10 setup for required BIOS changes.

## Validation

Local validation is limited to formatting, Python syntax and synthetic
read-only parser cases; Nix evaluation, `nix flake check` and builds belong in
GitHub Actions. CI must include the T1/T2/T3 NixOS configurations after the
parent integrates these files. The packaged command has not been deployed to
the fleet. Live findings above came from existing read-only tools; no packages
were installed on T1.
