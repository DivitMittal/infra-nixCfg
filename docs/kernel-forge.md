# Kernel Forge

Status: active. The proving host (`KFORGE`) is registered; validation and
escalation are documented in [kernel-forge-validation.md](./kernel-forge-validation.md).
This document records the scope, architecture, and workflow
for the **Kernel Forge** track — a kernel-engineering surface inside this
multi-platform Nix flake for patch-queue work, backport practice, and out-of-tree
driver integration.

## Purpose

Kernel engineering has its own failure mode: an aggressive master-track kernel or
an unvetted patch can take down a production host on the next rebuild. The forge
track exists to absorb that risk inside an explicit, opt-in module so the rest of
the configuration keeps shipping. Concretely, the track supports:

- **Kernel backporting practice** — evaluating mainline fixes against a stable
  base before deciding whether to carry them downstream.
- **Patch queue management** — cataloging, applying, and pruning instrumentation
  Kconfig deltas and feature patches against a known kernel revision.
- **Kernel configuration deltas** — comparing `pkgs.master` vs. `pkgs.stable`
  behaviour, Kconfig state, and module coverage from one host definition.
- **Out-of-tree driver integration** — staging drivers (v4l2loopback, EVDI,
  DisplayLink) against a controlled profile before they ever reach a real
  workstation.

The track is also kept useful as a long-term maintenance surface: the option
declarations, the patch catalog directory, and the assertion shape will outlive
any single driver experiment.

## Design principles

- **Explicit attachment.** The module is exported as
  `flake.nixosModules.kernel-forge` in `modules/default.nix` and is deliberately
  _not_ part of any `all`/default bundle. A host opts in by listing the module
  in its `additionalModules` and setting `os.kernelForge.enable = true`. Two
  assertions guard attachment: `acknowledgeBreakage` must be true, and
  `config.hostSpec.hostName` must appear in `allowedHostNames`. Production
  hosts (`T2`, `ASL1N`, `VPS1`, `VPS2`) are never on that list.
- **Proving host first.** A dedicated VM-first host (`KFORGE`, planned,
  registered via `hosts/nixos/enum.nix` `additionalModules`) validates every
  kernel change before any hardware escalation. Hardware variants
  (e.g. `T2-forge`) are a downstream concern, never the first landing site.
- **Explicit failure over silent skipping.** Assertions fail the evaluation
  outright; there is no fallback path that quietly reverts to the host's
  default kernel once the profile is broken.
- **Master-track kernel by default.** `os.kernelForge.kernelPackages` defaults
  to `pkgs.master.linuxPackages_latest` (the flake's `mkCfg` exposes nixpkgs-
  master as `pkgs.master`). `pkgs.stable` is available for comparison runs.
- **Profile ownership.** `boot.kernelPackages` is set with `lib.mkForce` — the
  forge track owns the kernel on hosts that enable it, overriding any
  hardware-profile default.

## Option surface

All options live under `os.kernelForge.*`.

| Option                   | Type         | Default                            | Description                                                                                                   |
| ------------------------ | ------------ | ---------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `enable`                 | `bool`       | `false`                            | Master-track kernel selection, patch queue, driver integration, and instrumentation tooling; opt-in per host. |
| `acknowledgeBreakage`    | `bool`       | `false`                            | Guard: the forge kernel track can and will break; the host owner must opt in explicitly.                      |
| `allowedHostNames`       | `listOf str` | `[]`                               | Hosts allowed to run the forge track; assertion enforces membership.                                          |
| `kernelPackages`         | `raw`        | `pkgs.master.linuxPackages_latest` | Kernel package set for the forge track; master/latest by default for maximum patch-queue relevance.           |
| `enablePatchQueue`       | `bool`       | `true`                             | Apply the kernel instrumentation profile (structured Kconfig deltas) from the patch catalog.                  |
| `enableBackports`        | `bool`       | `false`                            | Apply the stable backport track from the patch catalog; fails evaluation if the catalog is empty.             |
| `enableV4l2Loopback`     | `bool`       | `false`                            | Build the v4l2loopback out-of-tree module against the forge kernel and load it at boot.                       |
| `enableEvdi`             | `bool`       | `false`                            | Build the evdi (DisplayLink) DRM module against the forge kernel; build + modinfo is the proving criterion.   |
| `enableTracingToolchain` | `bool`       | `true`                             | eBPF/ftrace/perf userland for kernel instrumentation profiles.                                                |
| `extraKernelParams`      | `listOf str` | `[]`                               | Additional kernel parameters for a host-specific forge profile.                                               |
| `extraModulePackages`    | `listOf raw` | `[]`                               | Additional kernel module derivations appended to `boot.extraModulePackages`.                                  |

When `enableTracingToolchain` is true, the forge track also installs
`perf`, `bpftools`, `bpftrace`, `bcc`, `trace-cmd`, `pciutils`, `usbutils`,
`ethtool`, `lshw`, `kmod`, `strace`, `sysstat`, and enables `services.fwupd`.

## Roadmap

- **Patch queue.** Land the catalog under `modules/hosts/nixos/kernel-forge/patches/`
  with instrumentation Kconfig deltas (eBPF/`/proc/config.gz` introspection,
  tracing tunables) and a stable backport track gated by `enableBackports`.
- **Driver integrations.** v4l2loopback first, then EVDI / DisplayLink; each
  staged through the same `enable*` → wiring sequence and validated on `KFORGE`.
- **Proving host.** Register `KFORGE` in `hosts/nixos/enum.nix` as
  `KFORGE = mkCfg { hostName = "KFORGE"; ... }` with a
  `hosts/nixos/profiles/kernel-forge-extreme.nix` profile in its
  `additionalModules` that imports the module and enables the full track.
- **Branch-scoped CI.** A forge-only CI lane that builds the `KFORGE` toplevel
  and VM on every change to the module or its patch catalog.
- **Hardware escalation.** Variants such as `T2-forge` only after VM validation
  proves a profile boot-clean and runtime-verified.

## Workflow

A change flows through a fixed sequence:

1. Edit the module or the patch catalog.
2. Evaluate the host's options to confirm the assertions resolve cleanly:

   ```sh
   nix eval .#nixosConfigurations.KFORGE.config.os.kernelForge --apply builtins.attrNames
   ```

3. Build the system toplevel and VM:

   ```sh
   nix build .#nixosConfigurations.KFORGE.config.system.build.toplevel
   nix build .#nixosConfigurations.KFORGE.config.system.build.vm
   ```

4. Boot the VM and run runtime verification: inspect `/proc/config.gz`,
   `bpftool prog show`, `bpftrace -l`, `perf list`, `trace-cmd list`.
5. Only after the VM run is green, consider extending the same profile to a
   hardware-escalation variant.
