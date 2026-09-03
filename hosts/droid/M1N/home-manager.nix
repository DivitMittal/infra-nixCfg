{
  # Merges with the shared bridge in common/hosts/droid/home-manager.nix, which
  # already sets useGlobalPkgs/backupFileExtension for the whole droid class.
  home-manager.config = ./_home.nix;
}
