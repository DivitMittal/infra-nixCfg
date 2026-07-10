{self, ...}: {
  # Forge-scoped checks. The broad flake-check workflow runs with --no-build,
  # so these stay eval-only there; actually building them is reserved for the
  # branch-scoped kernel-forge workflow and local runs.
  flake.checks.x86_64-linux = {
    kernel-forge-kforge-toplevel = self.nixosConfigurations.KFORGE.config.system.build.toplevel;
    kernel-forge-kforge-vm = self.nixosConfigurations.KFORGE.config.system.build.vm;
    # Driver derivations pulled from the *host's* kernel package set, so a
    # kernel bump that breaks either out-of-tree module fails these checks
    # without building the whole system.
    kernel-forge-v4l2loopback = self.nixosConfigurations.KFORGE.config.boot.kernelPackages.v4l2loopback;
    kernel-forge-evdi = self.nixosConfigurations.KFORGE.config.boot.kernelPackages.evdi;
  };
}
