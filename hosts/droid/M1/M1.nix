{pkgs, ...}: {
  user = rec {
    uid = 10732;
    gid = uid;
    shell = "${pkgs.fish}/bin/fish";
  };

  ## X11 GUI session via termux-x11 (see common/hosts/droid/gui.nix)
  termux-gui = {
    enable = true;
    # GPU acceleration — set to `false` until `pkgs/custom/mesa-turnip/package.nix`
    # is pinned to a real source; the X11 path works without it.
    gpu.enable = true;
    gpu.driver = "auto";
  };
}
