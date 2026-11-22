{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  # The GUI package already supplies mullvad and mullvad-daemon. Selecting it
  # for CLI use avoids merging two independently versioned implementations.
  programs.vpn.mullvadPackage = lib.mkIf hostPlatform.isLinux pkgs.mullvad-vpn;
  home.packages = lib.attrsets.attrValues {
    mullvad-vpn =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.mullvad-vpn
      else pkgs.mullvad-vpn;
    tailscale =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.tailscale-app
      else pkgs.tailscale;
  };

  homebrew.casks = lib.optionals hostPlatform.isDarwin ["cloudflare-warp"];
}
