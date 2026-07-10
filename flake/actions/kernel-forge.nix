{
  common-permissions,
  environment,
  common-actions,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/kernel-forge.yml" = {
    on = {
      workflow_dispatch = {};
      push.branches = ["forge/kernel*" "feat/kernel-forge*"];
    };
    jobs.forge-eval = {
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions
        ++ [
          {
            name = "Evaluate KFORGE kernel + patch queue";
            run = ''
              nix eval --accept-flake-config .#nixosConfigurations.KFORGE.config.boot.kernelPackages.kernel.version
              nix eval --accept-flake-config .#nixosConfigurations.KFORGE.config.os.kernelForge.enable
              nix eval --accept-flake-config .#nixosConfigurations.KFORGE.config.boot.kernelPatches --apply "ps: map (p: p.name) ps"
            '';
          }
          {
            name = "Dry-run KFORGE toplevel";
            run = "nix -vL build --accept-flake-config --dry-run .#checks.x86_64-linux.kernel-forge-kforge-toplevel";
          }
        ];
    };
    jobs.forge-kernel-build = {
      # Kernel builds are too heavy for every push.
      "if" = "github.event_name == 'workflow_dispatch'";
      timeout-minutes = 360;
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions
        ++ [
          {
            name = "Build KFORGE driver checks";
            run = "nix -vL build --accept-flake-config .#checks.x86_64-linux.kernel-forge-v4l2loopback .#checks.x86_64-linux.kernel-forge-evdi --show-trace";
          }
          {
            name = "Build KFORGE toplevel";
            run = "nix -vL build --accept-flake-config .#checks.x86_64-linux.kernel-forge-kforge-toplevel --show-trace";
          }
        ];
    };
  };
}
