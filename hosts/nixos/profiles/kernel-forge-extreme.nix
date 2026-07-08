# Extreme profile for the full forge surface: master-track kernel, patch queue,
# both driver tracks, and the tracing toolchain. Attach only to proving hosts;
# hardware escalation variants get their own profiles.
{self, ...}: {
  imports = [self.outputs.nixosModules.kernel-forge];

  os.kernelForge = {
    enable = true;
    acknowledgeBreakage = true;
    allowedHostNames = ["KFORGE"];
    enableV4l2Loopback = true;
    enableEvdi = true;
  };
}
