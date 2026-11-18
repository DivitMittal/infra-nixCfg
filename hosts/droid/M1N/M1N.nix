{pkgs, ...}: {
  # Android's uid for com.termux.launcher.nix on this phone, read with
  # `adb shell stat -c %u /data/data/com.termux.launcher.nix` (2026-11-19).
  # Pinned because deploys build off-device, where `id -u` is the builder's.
  # Changes if the app is reinstalled.
  user = {
    uid = 10317;
    gid = 10317;
    shell = "${pkgs.fish}/bin/fish";
  };

  # Edit, then `nix-on-droid switch --flake .#M1N`.
  launcher.toolkits = {
    shell = true;
    eyeCandy = true;
    editor = true;
    build = true;
    gui = true;
  };
}
