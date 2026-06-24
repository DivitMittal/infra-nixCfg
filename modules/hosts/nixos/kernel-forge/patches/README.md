# Kernel Forge — patch queue

## Purpose

The patch queue keeps kernel deltas versioned, reviewable, and per-entry
documented, so nothing reaches a built kernel without a record of what it is,
where it came from, and why it is there. It is imported by
`modules/hosts/nixos/kernel-forge.nix` as
`import ./kernel-forge/patches {inherit lib;}` and feeds `boot.kernelPatches`.

There are two tracks:

- **instrumentation** — structured Kconfig deltas carried as a `patch = null`
  kernel patch. No source blob is fetched; the deltas live entirely in
  `default.nix` as `structuredExtraConfig`. This is the maintainable way to keep
  a kernel instrumentation profile versioned and diffable.
- **backports** — real stable fixes pulled via `pkgs.fetchpatch`. Each entry is a
  `.patch` from the Greg KH stable tree applied on top of the base kernel.

The catalog returns `{ instrumentation = [...]; backports = [...]; }`.

## Entry requirements

Every **backport** entry must record, as a comment block above the entry:

- **upstream mainline SHA** — the commit on Linus' tree the stable fix backports.
- **stable commit URL** — the `gregkh/linux` commit/`.patch` URL actually fetched.
- **subject** — the commit's one-line title.
- **why it matters** — the bug/security/effect this fixes on this host.
- **kernel version verified against** — the exact tag (e.g. `v7.1.3`) the
  nixpkgs-pinned release builds.
- **how it was verified** — a containment grep of the touched function/symbol
  against the target tag, proving the fix is NOT already present (so applying it
  will not fuzz-fail) and NOT yet needed elsewhere.

Instrumentation entries are config deltas, not source patches, so they record the
capability group each `structuredExtraConfig` block turns on instead of a SHA.

## Current queue

The instrumentation entry (`kernel-forge-instrumentation`) enables these
capability groups via `structuredExtraConfig`:

- **config.gz** — `IKCONFIG`, `IKCONFIG_PROC`: `/proc/config.gz` exposes the
  running kernel's compiled config.
- **eBPF / BTF** — `BPF`, `BPF_SYSCALL`, `BPF_JIT`, `DEBUG_INFO_BTF`: BPF
  programs, the syscall surface, JIT, and BTF for CO-RE/`bpftool`.
- **ftrace** — `FTRACE`, `FUNCTION_TRACER`, `FUNCTION_GRAPH_TRACER`,
  `DYNAMIC_FTRACE`: function and graph tracing with runtime patching.
- **kprobes / uprobes** — `KPROBES`, `UPROBES`, `KPROBE_EVENTS`,
  `UPROBE_EVENTS`: dynamic kernel and userspace probes and their trace events.
- **perf** — `PERF_EVENTS`: hardware/software counters for `perf` and
  `trace-cmd`.
- **modversions / unload** — `MODULE_UNLOAD`, `MODVERSIONS`: loadable module
  support with version CRCs and the ability to unload, needed for driver work.
- **debugfs** — `DEBUG_FS`: debugfs mount for tracer/ftrace control files.

Runtime verification (on a host running the forge kernel):

```sh
zgrep -E "IKCONFIG|BPF|FTRACE" /proc/config.gz
bpftool feature probe
```

The backport track is empty — see the next section.

## Backport track: verified-merged (disabled)

The first candidate examined for this track is:

- **subject** — `NFSv4/pNFS: reject zero-length r_addr in nfs4_decode_mp_ds_addr`
- **upstream mainline SHA** — `41fe0f7b84f0cb822ae10ab08592996a592b2a25`
- **stable commit URL** —
  https://github.com/gregkh/linux/commit/427ab81a811dab4bca9d19f82eec5847ae42646e.patch
- **kernel version verified against** — `v7.1.3` (the kernel
  `linuxPackages_latest` builds at nixpkgs locked rev
  `ef43073264cd5a38478250c3c66b9a2bf480036c`).
- **how it was verified** — the fix was backported into the `linux-7.1.y` stable
  series **exactly at `v7.1.3`**. Base `v7.1` and `v7.1.1`/`v7.1.2` did not have
  it; `v7.1.3` does. The containment grep therefore returns the fix already
  present in the target tag.

**Why it is not applied:** the kernel this flake builds is already `v7.1.3`, so
the fix is merged into our base. Applying the stable patch on top would fail
fuzz/reverse checks (the context lines already contain the change). Carrying it
would be dead weight and a build breaker, not a fix.

**Queue state:** the stable `linux-7.1.y` branch tip is the `v7.1.3` tag;
nothing is queued for `v7.1.4` yet. There is currently **no released-but-missing
stable fix** to carry, so the backport track ships empty. The NFS entry is kept
here as provenance and as the template shape for the first real entry.

**Re-evaluation trigger:** re-enable a backport entry only on a kernel bump
where a new stable queue lands fixes that are not yet in the
nixpkgs-pinned release (i.e. a fix exists in `v7.1.<N>` but the pinned build is
at `v7.1.<N-1>` or earlier). At that point, record the new candidate's full
provenance above and add it to `backports`.

## Adding a backport

Workflow, end to end:

1. **Pick** a fix from the Greg KH stable queue (`linux-<ver>.y` branch) that is
   NOT yet in the nixpkgs-pinned release the forge kernel builds. Confirm via the
   containment grep that the touched function lacks the fix at the pinned tag.
2. **Thread `pkgs`** into the catalog import in `kernel-forge.nix`
   (`import ./kernel-forge/patches {inherit lib pkgs;}`) and add `pkgs` to the
   `default.nix` signature.
3. **Add the entry** with `pkgs.fetchpatch`, starting from `lib.fakeHash`:
   ```nix
   {
     name = "<short-slug>";
     patch = pkgs.fetchpatch {
       url = "https://github.com/gregkh/linux/commit/<stable-sha>.patch";
       hash = lib.fakeHash;
     };
   }
   ```
4. **Pin the real hash** — the first build fails with a hash mismatch that names
   the correct `sha256-...`; copy it back into `hash`.
5. **Enable the track** on the host: `os.kernelForge.enableBackports = true;`
   (the module asserts the catalog is non-empty, so an empty catalog fails
   evaluation explicitly rather than silently no-op'ing).
6. **Build** to confirm: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
   (or the equivalent `nixos-rebuild build` flake invocation).
