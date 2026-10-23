{
  # Shared home-manager bridge for the droid class. Host-specific dirs (e.g.
  # hosts/droid/M1N) may additionally set `home-manager.config` themselves —
  # submodule-typed options merge definitions from multiple files.
  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-bak";
    config = {
      # Read the changelog before changing this value.
      home.stateVersion = "26.05";

      imports = [./_shortcuts.nix];
    };
  };
}
