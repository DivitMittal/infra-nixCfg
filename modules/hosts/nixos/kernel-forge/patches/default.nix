## Kernel Forge — patch catalog
# Importable as `import ./kernel-forge/patches {inherit lib;}`. Returns two
# tracks that feed boot.kernelPatches in kernel-forge.nix:
#   - instrumentation: structured Kconfig deltas (patch = null), no source fetch
#   - backports:       real stable fixes via pkgs.fetchpatch (empty by default)
{lib}: {
  ## Instrumentation track
  # Structured Kconfig delta carried as a `patch = null` kernel patch. This keeps
  # the kernel instrumentation profile versioned, diffable, and reviewable without
  # touching a .patch blob. Capability groups: config.gz, eBPF/BTF, ftrace,
  # kprobes/uprobes, perf, modversions/unload, debugfs. See README.md.
  instrumentation = [
    {
      name = "kernel-forge-instrumentation";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        ## /proc/config.gz visibility
        IKCONFIG = yes;
        IKCONFIG_PROC = yes;
        ## eBPF / BTF
        BPF = yes;
        BPF_SYSCALL = yes;
        BPF_JIT = yes;
        DEBUG_INFO_BTF = yes;
        ## tracing
        FTRACE = yes;
        FUNCTION_TRACER = yes;
        FUNCTION_GRAPH_TRACER = yes;
        DYNAMIC_FTRACE = yes;
        ## dynamic probes
        KPROBES = yes;
        UPROBES = yes;
        KPROBE_EVENTS = yes;
        UPROBE_EVENTS = yes;
        ## perf
        PERF_EVENTS = yes;
        ## driver work
        MODULE_UNLOAD = yes;
        MODVERSIONS = yes;
        ## diagnostics
        DEBUG_FS = yes;
      };
    }
  ];

  ## Backport track
  # Empty by design: there is currently no released stable fix missing from the
  # kernel this flake builds (7.1.3 at the pinned nixpkgs rev). Entries are added
  # only when a stable-queue fix is NOT yet in the nixpkgs-pinned release.
  #
  # Active entry shape (when a backport lands) — note this requires threading
  # `pkgs` into the catalog import site and adding `pkgs` to the signature above:
  #
  #   {
  #     name = "nfsv4-pnfs-reject-zero-length-r-addr";
  #     patch = pkgs.fetchpatch {
  #       url = "https://github.com/gregkh/linux/commit/<stable-sha>.patch";
  #       hash = lib.fakeSha256;
  #     };
  #   }
  #
  # First candidate (NFSv4/pNFS zero-length r_addr) was verified already-merged
  # at v7.1.3 and is intentionally NOT applied; full provenance in README.md.
  backports = [];
}
