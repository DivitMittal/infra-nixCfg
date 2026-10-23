{inputs, ...}: let
  # The fork's `launcher` flake template. Its scripts and config files are reused
  # straight from the pinned input instead of being vendored, so they track the
  # fork on `nix flake update nix-on-droid-launcher`.
  launcherTemplate = "${inputs.nix-on-droid-launcher}/templates/launcher";
in {
  # Merges with the shared bridge in common/hosts/droid/home-manager.nix, which
  # already sets useGlobalPkgs/backupFileExtension for the whole droid class.
  home-manager.config = {
    imports = [./_home.nix];
    _module.args = {inherit launcherTemplate;};
  };
}
