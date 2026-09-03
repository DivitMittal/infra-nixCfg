{pkgs, ...}: {
  # user.uid/gid default to `id -u`/`id -g`, auto-detected at build time — accurate
  # when building on-device (the running process's uid *is* the app's Android uid).
  # M1 (hosts/droid/M1/M1.nix) pins these explicitly instead; if this host ever needs
  # the same (e.g. cross-building off-device), find the value post-install via
  # `id -u` inside a com.termux.launcher.nix session, or `stat -c %u ~` and pin it here.
  user = {
    shell = "${pkgs.fish}/bin/fish";
  };
}
