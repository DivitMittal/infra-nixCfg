{
  config,
  hostPlatform,
  inputs,
  lib,
  ...
}: {
  imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

  ## Only installs brew itself: Homebrew's installer refuses Intel Macs, but brew
  ## still runs there. Packages stay with home-manager-brew (common/home/brew.nix),
  ## which bootstraps brew on every other platform. No declarative taps: pinning
  ## homebrew-core/cask forces full git clones instead of the JSON API
  nix-homebrew = lib.mkIf hostPlatform.isx86_64 {
    enable = true;
    user = config.hostSpec.username;
    mutableTaps = true;
    autoMigrate = true;
  };
}
