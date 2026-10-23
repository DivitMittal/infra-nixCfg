{pkgs, ...}: {
  # user.uid/gid default to `id -u`/`id -g`, auto-detected at build time — accurate
  # when building on-device (the running process's uid *is* the app's Android uid).
  # M1 (hosts/droid/M1/M1.nix) pins these explicitly instead; if this host ever needs
  # the same (e.g. cross-building off-device), find the value post-install via
  # `id -u` inside a com.termux.launcher.nix session, or `stat -c %u ~` and pin it here.
  user = {
    shell = "${pkgs.fish}/bin/fish";
  };

  # On top of common/hosts/droid/termux.nix. The fork points these at the
  # launcher's package name, so they reach com.termux.launcher.nix's socket.
  android-integration = {
    termux-wake-lock.enable = true;
    termux-wake-unlock.enable = true;
    # `gx` in neovim and anything else shelling out to xdg-open has no handler
    # inside the proot; this aliases it to termux-open.
    xdg-open.enable = true;
  };

  # `nix search`/`nix run`/`nix shell` and on-device flake switches.
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
}
