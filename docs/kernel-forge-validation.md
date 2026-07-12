# Kernel Forge — validation & escalation

Companion to [`kernel-forge.md`](./kernel-forge.md). Defines the verification
matrix, CI lanes, escalation ordering, and backport-track status for the
Kernel Forge track on this flake.

## Verification matrix

The track is validated in three strictly ordered stages. Each stage must
be green before the next is attempted.

### Evaluation

Run anywhere the flake resolves (including darwin). Catches assertion
failures, option-shape regressions, and patch-catalog wiring without paying
for a kernel build.

```sh
nix -vL flake check --all-systems --no-build
nix eval .#nixosConfigurations.KFORGE.config.os.kernelForge.enable
nix eval .#nixosConfigurations.KFORGE.config.boot.kernelPackages.kernel.version
nix eval .#nixosConfigurations.KFORGE.config.boot.kernelPatches --apply "ps: map (p: p.name) ps"
nix eval .#nixosConfigurations.KFORGE.config.boot.extraModulePackages --apply "ms: map (m: m.name or m.pname) ms"
```

### Build

Requires an `x86_64-linux` builder. The instrumentation Kconfig delta
forces the kernel to rebuild from source rather than reuse the nixpkgs
cache, so the first build is the expensive one.

```sh
nix build .#checks.x86_64-linux.kernel-forge-v4l2loopback --show-trace
nix build .#checks.x86_64-linux.kernel-forge-evdi --show-trace
nix build .#nixosConfigurations.KFORGE.config.system.build.toplevel --show-trace
nix build .#nixosConfigurations.KFORGE.config.system.build.vm --show-trace
```

Then prove isolation — other hosts must still build untouched by the
forge track:

```sh
nix build .#nixosConfigurations.WSL.config.system.build.toplevel --show-trace
nix build .#nixosConfigurations.T2.config.system.build.toplevel --show-trace
```

### Runtime (VM)

Boot `result/bin/run-KFORGE-vm` from the previous step, then verify the
instrumentation profile and the driver modules inside the live system:

```sh
uname -a
cat /proc/version
zgrep -E "IKCONFIG|BPF|BTF|FTRACE|KPROBES|UPROBES|PERF_EVENTS|MODVERSIONS" /proc/config.gz
modinfo v4l2loopback && lsmod | grep v4l2loopback
modinfo evdi || true   # runtime load is hardware/userland dependent; build + modinfo is the proving criterion
bpftool feature probe | head
bpftrace --info
perf --version
trace-cmd --version
```

## CI lanes

- **Broad `flake-check` workflow.** Runs `nix flake check --all-systems
--no-build` across every push; evaluates forge checks but does not build
  them. Kernel builds are too heavy for the general lane.
- **`forge-eval` (`.github/workflows/kernel-forge.yml`).** Branch-scoped to
  `forge/kernel*` and `feat/kernel-forge*`. Pushes only: evaluates the
  KFORGE option set, the patch queue (`boot.kernelPatches` names), and a
  dry-run of the toplevel check.
- **`forge-kernel-build`.** Same workflow, `workflow_dispatch` only, with
  a 360-minute timeout. Builds the two driver checks
  (`kernel-forge-v4l2loopback`, `kernel-forge-evdi`) and the toplevel. This
  is the lane that actually compiles the forge kernel.

## Escalation path

Strict ordering. The deploy nodes run without magic rollback, so a forge
kernel that skips ahead to a VPS is a manual-recovery incident — exactly
the failure mode the proving host exists to absorb first.

1. KFORGE toplevel + VM build green.
2. KFORGE VM boots; instrumentation Kconfig groups and the tracing
   toolchain (perf, bpftool, bpftrace, trace-cmd) are verified at runtime.
3. Existing hosts still evaluate and build (the WSL/T2 isolation builds
   above). The forge module must not bleed into production hosts.
4. Only then: hardware-variant profiles. `T2-forge` must preserve the
   nixos-hardware `apple-t2` expectations; `ASL1N-forge` must not blindly
   override the Asahi kernel stack. Each variant profile is its own
   `additionalModules` entry and its own `allowedHostNames` membership.
5. VPS variants last, if ever. Deploy nodes run `magicRollback = false`,
   so a broken forge kernel on a VPS means manual recovery — keep
   `VPS1` / `VPS2` off the track until hardware variants are proven.
6. `hosts/deploy.nix` production nodes are not modified until the forge
   track is proven end-to-end on the proving host and (where applicable)
   on a hardware variant.

## Backport track status

Empty by verification. The first candidate considered —
`NFSv4/pNFS: reject zero-length r_addr in nfs4_decode_mp_ds_addr`
(mainline `41fe0f7b84f0cb822ae10ab08592996a592b2a25`) — is already merged
into the pinned kernel (`v7.1.3`); see the patch catalog README for
provenance and the containment-grep result. Carrying the stable patch on
top would fail the fuzz/reverse check and break the build, so it is not
applied. `enableBackports = true` with an empty catalog therefore fails
evaluation by design (the module asserts `cfg.enableBackports ->
patchCatalog.backports != []`), which is the desired explicit-failure
behavior — an empty catalog never silently becomes an unpatched kernel.
