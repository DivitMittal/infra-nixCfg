{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.os.kernelForge;

  inherit (lib) literalExpression mkEnableOption mkIf mkMerge mkOption types;
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
      description = "Declare the patch queue surface now; wiring follows with the patch catalog under ./kernel-forge/patches.";
    };

    enableBackports = mkOption {
      type = types.bool;
      default = false;
      description = "Stable-backport track; off until a currently-applicable backport is verified.";
    };

    enableV4l2Loopback = mkOption {
      type = types.bool;
      default = false;
      description = "Declare v4l2loopback driver integration now; wiring follows in a later change.";
    };

    enableEvdi = mkOption {
      type = types.bool;
      default = false;
      description = "Declare EVDI driver integration now; wiring follows in a later change.";
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
      ];

      # mkForce is deliberate; the forge track owns the kernel on hosts that
      # enable it, overriding hardware-profile defaults.
      boot.kernelPackages = lib.mkForce cfg.kernelPackages;
      boot.kernelParams = cfg.extraKernelParams;
      boot.extraModulePackages = cfg.extraModulePackages;
    }

    (mkIf cfg.enableTracingToolchain {
      environment.systemPackages = [
        cfg.kernelPackages.perf
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
