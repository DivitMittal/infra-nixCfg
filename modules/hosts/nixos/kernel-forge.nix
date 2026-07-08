{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.os.kernelForge;

  inherit (lib) literalExpression mkEnableOption mkIf mkMerge mkOption types;

  patchCatalog = import ./kernel-forge/patches {inherit lib;};
in {
  ## Kernel Forge
  # Kernel Forge is a proving-host-first kernel engineering track for this flake.
  # It stays explicitly attached so master-track kernels, patch queues, and
  # instrumentation changes cannot drift onto production hosts by aggregation.
  # Hardware escalation should happen only after a host validates the profile.
  options.os.kernelForge = {
    enable = mkEnableOption "master-track kernel selection, patch queue, driver integration and instrumentation tooling; opt-in per host";

    acknowledgeBreakage = mkOption {
      type = types.bool;
      default = false;
      description = "Guard: the forge kernel track can and will break; the host owner must opt in explicitly.";
    };

    allowedHostNames = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Hosts allowed to run the forge track; assertion enforces membership.";
    };

    kernelPackages = mkOption {
      type = types.raw;
      default = pkgs.master.linuxPackages_latest;
      defaultText = literalExpression "pkgs.master.linuxPackages_latest";
      description = "Kernel package set for the forge track; master/latest by default for maximum patch-queue relevance.";
    };

    enablePatchQueue = mkOption {
      type = types.bool;
      default = true;
      description = "Apply the kernel instrumentation profile (structured Kconfig deltas) from the patch catalog.";
    };

    enableBackports = mkOption {
      type = types.bool;
      default = false;
      description = "Apply the stable backport track from the patch catalog; fails evaluation if the catalog is empty.";
    };

    enableV4l2Loopback = mkOption {
      type = types.bool;
      default = false;
      description = "Build the v4l2loopback out-of-tree module against the forge kernel and load it at boot (virtual camera / capture pipelines).";
    };

    enableEvdi = mkOption {
      type = types.bool;
      default = false;
      description = "Build the evdi (DisplayLink) out-of-tree DRM module against the forge kernel; build + modinfo is the proving criterion, runtime load is hardware/userland dependent.";
    };

    enableTracingToolchain = mkOption {
      type = types.bool;
      default = true;
      description = "eBPF/ftrace/perf userland for kernel instrumentation profiles.";
    };

    extraKernelParams = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional kernel parameters for a host-specific forge profile.";
    };

    extraModulePackages = mkOption {
      type = types.listOf types.raw;
      default = [];
      description = "Additional kernel module derivations appended to boot.extraModulePackages.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.acknowledgeBreakage;
          message = "os.kernelForge runs a master-track kernel and requires acknowledgeBreakage = true.";
        }
        {
          assertion = lib.elem config.hostSpec.hostName cfg.allowedHostNames;
          message = "Host ${config.hostSpec.hostName} must be listed in os.kernelForge.allowedHostNames before enabling the forge track; this guards against accidental attachment to production hosts.";
        }
        {
          # Explicit failure instead of a silent no-op: enabling the backport
          # track with an empty catalog would otherwise build an unpatched kernel.
          assertion = cfg.enableBackports -> patchCatalog.backports != [];
          message = "os.kernelForge.enableBackports is enabled but the backport track is empty; add a verified entry to modules/hosts/nixos/kernel-forge/patches/default.nix or disable the flag.";
        }
      ];

      # mkForce is deliberate; the forge track owns the kernel on hosts that
      # enable it, overriding hardware-profile defaults.
      boot.kernelPackages = lib.mkForce cfg.kernelPackages;
      boot.kernelParams = cfg.extraKernelParams;
      boot.extraModulePackages = cfg.extraModulePackages;
      boot.kernelPatches =
        lib.optionals cfg.enablePatchQueue patchCatalog.instrumentation
        ++ lib.optionals cfg.enableBackports patchCatalog.backports;
    }

    # Runtime verification inside the proving host: `modinfo v4l2loopback`
    # (shows the forge-built module metadata) and `lsmod | grep v4l2loopback`
    # (confirms it loaded at boot) — both must succeed.
    (mkIf cfg.enableV4l2Loopback {
      # Out-of-tree module packages must come from config.boot.kernelPackages so
      # they are compiled against the forge kernel actually selected (post-mkForce),
      # not against whatever pkgs default the host would otherwise use.
      boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
      boot.kernelModules = ["v4l2loopback"];
    })

    (mkIf cfg.enableEvdi {
      # evdi tracks kernel internals closely and is the canary for master-kernel
      # breakage. Fail evaluation loudly if the selected kernel package set does
      # not expose it, rather than silently shipping a system without the track.
      assertions = [
        {
          assertion = config.boot.kernelPackages ? evdi;
          message = "os.kernelForge.enableEvdi = true, but the selected kernelPackages set does not expose an `evdi` package for this kernel; pin a compatible kernel or disable the evdi track.";
        }
      ];

      boot.extraModulePackages = [config.boot.kernelPackages.evdi];
      # No boot.kernelModules entry on purpose: loading evdi is only meaningful
      # with DisplayLink hardware/userland present. On the VM proving host the
      # acceptance criterion is build success + `modinfo evdi`.
    })

    (mkIf cfg.enableTracingToolchain {
      environment.systemPackages = [
        # nixpkgs detached perf from linuxPackages (the old attribute is a
        # deprecation alias); take it from the master channel so it stays
        # aligned with the default master-track kernel.
        pkgs.master.perf
        pkgs.bpftools
        pkgs.bpftrace
        pkgs.bcc
        pkgs.trace-cmd
        pkgs.pciutils
        pkgs.usbutils
        pkgs.ethtool
        pkgs.lshw
        pkgs.kmod
        pkgs.strace
        pkgs.sysstat
      ];

      services.fwupd.enable = true;
    })
  ]);
}
