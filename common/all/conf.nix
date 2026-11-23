{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkDefault;
  # The flake's own nixConfig caches (yazi, wezterm, numtide, vicinae), so a
  # build that doesn't accept flake config, or runs as an untrusted user,
  # still uses them. flake.nix stays the one place to list them.
  flakeCaches = (import ../../flake.nix).nixConfig;
in {
  nix = {
    enable = true;
    package = mkDefault pkgs.nixVersions.latest;
    checkConfig = mkDefault true;

    settings = {
      experimental-features = ["nix-command" "flakes"];
      accept-flake-config = mkDefault true;

      # Enable building aarch64 packages for nix-on-droid deployment
      # Uses Rosetta 2 (Apple Silicon), QEMU (Intel Mac/Linux)
      extra-platforms = mkDefault ["aarch64-linux" "aarch64-darwin"];

      connect-timeout = 5;
      log-lines = 25;
      min-free = 128000000; # 128MB
      max-free = 1000000000; # 1GB
      warn-dirty = mkDefault true;

      use-xdg-base-directories = mkDefault true;
      substituters =
        [
          "https://divitmittal.cachix.org"
          "https://nix-community.cachix.org"
          "https://nix-on-droid.cachix.org"
        ]
        ++ flakeCaches.extra-substituters;
      trusted-public-keys =
        [
          "divitmittal.cachix.org-1:Fx7nQrvET1RKTTrxQHMDP/Relbu072af/MFG4BYvpjw="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "nix-on-droid.cachix.org-1:56snoMJTXmE7wm+67YySRoTY64Zkivk9RT4QaKYgpkE="
        ]
        ++ flakeCaches.extra-trusted-public-keys;

      trusted-users = ["${config.hostSpec.username}"];
    };
  };
}
