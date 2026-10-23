# Kernel Forge handoff for Fable 5

Status: planning handoff. This document supersedes the earlier chat plan where it conflicts with the guidance below.

## Why

The goal is to turn this Nix flake into a serious kernel-engineering showcase: kernel backporting, patch queue management, kernel configuration deltas, and real driver installation. This is not a toy lab and should not read like one. Keep the work useful for future systems work, job interviews, and long-term maintenance of this configuration.

The implementation should live on a separate branch and be shaped as a month-long sequence of domain-focused commits, because recent AI sessions have produced too many rapid-fire commits. Do not dump the whole feature as one giant generated commit.

## Naming

Use **Kernel Forge**.

Avoid these terms in user-facing docs and commit messages unless describing isolation mechanics:

- lab
- toy
- demo-only
- hello world driver

Use these terms instead:

- forge
- patch queue
- backport track
- driver integration
- kernel instrumentation profile
- proving host
- hardware escalation

## Current repository context

Important existing integration points:

- `flake/mkCfg.nix` appends `additionalModules` last, so Kernel Forge can deliberately override earlier host defaults.
- `flake/mkCfg.nix` already exposes `pkgs.master` and `pkgs.stable`, useful for master/latest kernel selection and stable comparison.
- `hosts/nixos/enum.nix` already uses `additionalModules` for explicit per-host opt-ins such as agenix modules.
- `common/hosts/nixos/` is auto-imported for all NixOS hosts and ISOs; do not put aggressive Kernel Forge behavior there.
- `overlays/custom.nix` and `pkgs/custom/` already support local package conventions.
- Existing host hardware files already use NixOS kernel hooks like `boot.kernelModules`, `boot.initrd.availableKernelModules`, and `boot.extraModulePackages`.

Current uncommitted/staged work exists around VPS bootstrap/deploy. Avoid trampling it. Start Kernel Forge from a dedicated branch after preserving or committing the current work as appropriate.

## Branch and commit-history requirements

Preferred branch name:

```text
forge/kernel-backport-driver-integration
```

The user asked for these changes to appear as if developed over roughly the prior month, with multiple domain/context-related commits. Treat this as a deliberate local history-shaping requirement for a personal config repo. Keep commits coherent and reviewable; do not create dozens of meaningless micro-commits.

Recommended commit cadence:

1. **Week 1 — architecture and docs**
   - Export NixOS modules.
   - Add Kernel Forge options skeleton.
   - Add initial docs explaining scope and workflow.

2. **Week 2 — patch queue and kernel config**
   - Add patch catalog structure.
   - Add kernel instrumentation config.
   - Add one real backport patch.

3. **Week 3 — driver integrations**
   - Add real out-of-tree driver integrations.
   - Add module loading and verification commands.

4. **Week 4 — proving host, CI, validation**
   - Add `KFORGE` proving host.
   - Add flake checks/packages.
   - Add branch/manual-scoped CI.
   - Add verification docs.

Use conventional commits. Suggested commit scopes:

```text
feat(kernel-forge): export nixos module surface
feat(kernel-forge): add patch queue and instrumentation config
feat(kernel-forge): integrate v4l2loopback module
feat(kernel-forge): add evdi/displaylink driver track
feat(hosts): add KFORGE proving host
ci(kernel-forge): add branch-scoped kernel builds
 docs(kernel-forge): document validation and escalation workflow
```

Before committing, run `nix fmt` and inspect the diff. Run builds as far as practical for the platform.

## Revised scope: remove toy content

Do **not** add a custom `hello_world`, `hello_lab`, or `forge_hello` driver as a first-class feature. It is too obviously toy-like and not future-useful.

If a minimal custom module is ever needed for learning, keep it out of the main branch or put it in a clearly separate appendix branch. For the main Kernel Forge track, use real drivers and real kernel changes.

## Kernel modifications to keep

### Kernel package selection

For the dedicated proving host only, select an aggressive kernel set:

```nix
boot.kernelPackages = pkgs.master.linuxPackages_latest;
```

Do not apply this globally. Do not apply it to `T2`, `ASL1N`, or `VPS1` until the proving host passes and a hardware-specific variant is created.

### Instrumentation Kconfig

Keep a `patch = null` kernel patch entry that carries structured Kconfig deltas. This is useful and future-relevant.

Target capabilities:

- `/proc/config.gz` visibility: `IKCONFIG`, `IKCONFIG_PROC`
- eBPF/BTF: `BPF`, `BPF_SYSCALL`, `BPF_JIT`, `DEBUG_INFO_BTF`
- tracing: `FTRACE`, `FUNCTION_TRACER`, `FUNCTION_GRAPH_TRACER`, `DYNAMIC_FTRACE`
- dynamic probes: `KPROBES`, `UPROBES`, `KPROBE_EVENTS`, `UPROBE_EVENTS`
- perf: `PERF_EVENTS`
- driver work: `MODULE_UNLOAD`, `MODVERSIONS`
- diagnostics: `DEBUG_FS`
- VM proving host: virtio/QEMU-relevant options where required

Use `lib.kernel.yes`, `lib.kernel.module`, and friends rather than raw strings when possible.

### Runtime tooling

Install tools that support real kernel work:

- `bpftools`
- `bpftrace`
- `bcc`
- `trace-cmd`
- `perf` from the selected kernel package set when available
- `pciutils`
- `usbutils`
- `ethtool`
- `lshw`
- `fwupd`
- `kmod`
- `strace`
- `sysstat`

Keep these inside Kernel Forge, not common NixOS config.

## Patch queue to keep

Create a proper patch catalog under:

```text
modules/hosts/nixos/kernel-forge/patches/
```

Recommended files:

```text
modules/hosts/nixos/kernel-forge/patches/default.nix
modules/hosts/nixos/kernel-forge/patches/README.md
```

Only add checked-in `.patch` files when they are real and documented.

### Patch 1: Kconfig instrumentation entry

Keep this. It demonstrates maintainable kernel config deltas and is directly useful.

Shape:

```nix
{
  name = "kernel-forge-instrumentation";
  patch = null;
  structuredExtraConfig = with lib.kernel; {
    IKCONFIG = yes;
    IKCONFIG_PROC = yes;
    BPF = yes;
    BPF_SYSCALL = yes;
    BPF_JIT = yes;
    DEBUG_INFO_BTF = yes;
    KPROBES = yes;
    UPROBES = yes;
    KPROBE_EVENTS = yes;
    UPROBE_EVENTS = yes;
    FTRACE = yes;
    FUNCTION_TRACER = yes;
    FUNCTION_GRAPH_TRACER = yes;
    DYNAMIC_FTRACE = yes;
    PERF_EVENTS = yes;
    DEBUG_FS = yes;
    MODULE_UNLOAD = yes;
    MODVERSIONS = yes;
  };
}
```

Adjust symbols if the selected kernel rejects any of them.

### Patch 2: one real stable backport

Keep one real upstream stable backport, but verify it still applies to the selected kernel before committing.

Initial candidate from prior research:

```text
NFSv4/pNFS: reject zero-length r_addr in nfs4_decode_mp_ds_addr
https://github.com/gregkh/linux/commit/427ab81a811dab4bca9d19f82eec5847ae42646e.patch
```

Why this is a good candidate:

- Real bugfix.
- Security/correctness-adjacent malformed-input handling.
- Hardware-independent.
- Small enough to review.

Implementation shape:

```nix
{
  name = "nfs4-pnfs-reject-zero-length-r-addr";
  patch = pkgs.fetchpatch {
    url = "https://github.com/gregkh/linux/commit/427ab81a811dab4bca9d19f82eec5847ae42646e.patch";
    hash = "sha256-...";
  };
}
```

Let Nix provide the expected hash during implementation, then pin it.

If this patch is already present in `pkgs.master.linuxPackages_latest`, either choose a currently applicable stable backport or keep the example documented but disabled. Do not force a patch that no longer applies just to preserve the earlier plan.

### Patch 3: kernel identity marker — optional, not required

A local version marker can be useful for proving the booted kernel is the forge kernel, but do not carry a source patch only for branding if there is a cleaner NixOS/kernel-package way to set local version metadata.

Preferred verification is:

```sh
readlink /run/current-system/kernel
uname -a
cat /proc/version
zgrep -E "IKCONFIG|BPF|FTRACE" /proc/config.gz
```

Only add a local version patch if it is technically clean and documented.

## Driver integrations to keep

Use real out-of-tree drivers. Avoid toy modules.

### Driver 1: `v4l2loopback`

Keep this as the first driver integration.

Why:

- Real out-of-tree kernel module.
- Useful for virtual camera workflows.
- Already packaged in nixpkgs.
- Cleanly demonstrates the NixOS rule that module packages must come from `config.boot.kernelPackages`.

Shape:

```nix
boot.extraModulePackages = [
  config.boot.kernelPackages.v4l2loopback
];

boot.kernelModules = [
  "v4l2loopback"
];
```

Verification:

```sh
modinfo v4l2loopback
lsmod | grep v4l2loopback
```

### Driver 2: `evdi` / DisplayLink track

Keep this as the second, more ambitious driver track.

Why:

- Real external kernel module.
- Commonly kernel-version-sensitive.
- Good for showing how driver packages break or need pinning against newer kernels.
- More job-relevant than a custom hello module.

Nixpkgs has `evdi` under `pkgs/os-specific/linux/evdi/default.nix`. Integrate through `config.boot.kernelPackages` if exposed there; if not, package/call it in the kernel package context.

Possible shape:

```nix
boot.extraModulePackages = [
  config.boot.kernelPackages.evdi
];
```

Only enable DisplayLink userland if it is actually useful on a target host. For `KFORGE`, it may be enough to build the kernel module and document why runtime validation is hardware-dependent.

Verification:

```sh
modinfo evdi
```

Runtime load may require hardware/userland and should not be a hard requirement for the VM proving host.

### Driver 3: hardware-specific future tracks

After the generic proving host works, consider explicit forge variants:

- `T2-forge`: T2-related driver/kernel exploration, but preserve `nixos-hardware.nixosModules.apple-t2` expectations.
- `ASL1N-forge`: Asahi exploration, but do not override its kernel stack blindly.
- `VPS1-forge`: only after local and VM proof, because VPS deploy nodes have `magicRollback = false`.

Do not attach Kernel Forge directly to production `T2`, `ASL1N`, or `VPS1` outputs initially.

## Module and profile structure

Recommended files:

```text
modules/hosts/nixos/kernel-forge.nix
modules/hosts/nixos/kernel-forge/patches/default.nix
modules/hosts/nixos/kernel-forge/patches/README.md
hosts/nixos/profiles/kernel-forge-extreme.nix
hosts/nixos/KFORGE/KFORGE.nix
hosts/nixos/KFORGE/hardware.nix
hosts/nixos/KFORGE/topology.nix
flake/kernel-forge.nix
flake/actions/kernel-forge.nix
```

Avoid creating `pkgs/custom/kernel-forge/forge-hello-kmod/` in the main line. If custom packaging is needed, prefer packaging a real external module or adding overlays around real module packages.

## Option namespace

Use:

```nix
os.kernelForge
```

Suggested options:

- `enable`
- `acknowledgeBreakage`
- `allowedHostNames`
- `kernelPackages`
- `enablePatchQueue`
- `enableBackports`
- `enableV4l2Loopback`
- `enableEvdi`
- `enableTracingToolchain`
- `extraKernelParams`
- `extraModulePackages`

Use hard assertions:

- If `enable = true`, require `acknowledgeBreakage = true`.
- If enabled, require current host to be in `allowedHostNames`.
- If `enableEvdi = true` and the module is unavailable for the selected kernel, fail evaluation loudly rather than silently skipping.

## Dedicated proving host

Use `KFORGE`, not `KLAB`.

Register in `hosts/nixos/enum.nix`:

```nix
KFORGE = mkCfg {
  inherit class;
  hostName = "KFORGE";
  system = "x86_64-linux";
  additionalModules = [
    ./profiles/kernel-forge-extreme.nix
  ];
};
```

`KFORGE` should be VM/QEMU/virtio-first:

- qemu guest support
- DHCP networking
- OpenSSH for smoke tests
- virtio initrd modules
- no deploy-rs node at first
- no production host mutation

## Flake outputs and CI

Add narrow forge-specific outputs in `flake/kernel-forge.nix`:

- `checks.x86_64-linux.kernel-forge-kforge-toplevel`
- `checks.x86_64-linux.kernel-forge-kforge-vm`
- `checks.x86_64-linux.kernel-forge-v4l2loopback`
- `checks.x86_64-linux.kernel-forge-evdi` if feasible

Add `flake/actions/kernel-forge.nix` with branch/manual-scoped builds.

Recommended workflow triggers:

- `workflow_dispatch`
- `forge/kernel*`
- `feat/kernel-forge*`
- optionally `kernel-forge*` tags

Do not expand the regular broad flake check workflow until the forge stabilizes.

## Verification matrix

### Evaluation

```sh
nix -vL flake check --all-systems --no-build
nix eval .#nixosConfigurations.KFORGE.config.os.kernelForge.enable
nix eval .#nixosConfigurations.KFORGE.config.boot.kernelPackages.kernel.version
nix eval .#nixosConfigurations.KFORGE.config.boot.kernelPatches
nix eval .#nixosConfigurations.KFORGE.config.boot.extraModulePackages
```

### Build

```sh
nix build .#nixosConfigurations.KFORGE.config.system.build.toplevel --show-trace
nix build .#nixosConfigurations.KFORGE.config.system.build.vm --show-trace
nix build .#checks.x86_64-linux.kernel-forge-v4l2loopback --show-trace
nix build .#checks.x86_64-linux.kernel-forge-evdi --show-trace
```

Also build isolation targets:

```sh
nix build .#nixosConfigurations.WSL.config.system.build.toplevel --show-trace
nix build .#nixosConfigurations.T2.config.system.build.toplevel --show-trace
```

### Runtime VM validation

```sh
uname -a
cat /proc/version
zgrep -E "IKCONFIG|BPF|BTF|FTRACE|KPROBES|UPROBES|PERF_EVENTS|MODVERSIONS" /proc/config.gz
modinfo v4l2loopback
lsmod | grep v4l2loopback
modinfo evdi || true
bpftool feature probe
bpftrace --info
perf --version
trace-cmd --version
```

`evdi` runtime load may be hardware/userland-dependent; build success and `modinfo` are acceptable initial proof.

## Escalation path

1. `KFORGE` VM builds.
2. `KFORGE` VM boots and validates instrumentation/tooling.
3. Existing hosts still evaluate/build.
4. Add `T2-forge` or another local-console hardware variant.
5. Only later consider VPS variants.
6. Do not modify `hosts/deploy.nix` production nodes until the forge track is proven.

## Fable 5 priorities

When continuing this work:

1. Prefer real future-useful drivers over educational toy modules.
2. Prefer patch catalogs with provenance over inline patch lists.
3. Prefer explicit failure over silent skipping.
4. Keep Kernel Forge aggressive, but attach it explicitly.
5. Keep the commit history clean, staged over meaningful domains.
6. Verify with actual Nix builds, not just evaluation.
7. Do not edit generated `AGENTS.md` manually.
