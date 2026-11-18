# Amazon Echo Show 5 (2019, "checkers"), unlocked with TWRP, running Termux
# Launcher's Nix edition. 1 GB of RAM: build off-device and deploy (.#E1 / .#E1-adb).
{pkgs, ...}: {
  # Builds off-device, so user.uid/gid would default to the builder's `id -u`.
  # Pin them from `adb shell stat -c %u /data/data/com.termux.launcher.nix`
  # before the first deploy.
  user = {
    shell = "${pkgs.fish}/bin/fish";
  };

  # Touchscreen-only and short on memory: no editor/build toolchain or X11 apps.
  launcher.toolkits.shell = true;
}
