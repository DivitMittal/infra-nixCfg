{
  pkgs,
  hostPlatform,
  lib,
  config,
  ...
}: let
  cfg = config.programs.vpn;

  # Homebrew's mullvad-vpn cask ships the `mullvad` CLI binary inside the .app
  # bundle (no separate formula/cask). Wrap it so `mullvad` resolves on $PATH
  # for terminal use, mirroring the soffice wrapper in home/gui/office.nix.
  mullvadCliWrapper = pkgs.writeShellScriptBin "mullvad" ''
    exec "${pkgs.brewCasks.mullvad-vpn}/Applications/Mullvad VPN.app/Contents/Resources/mullvad" "$@"
  '';
in {
  options.programs.vpn = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install VPN CLI tooling (mullvad + tailscale). Disabling disables
        both, regardless of platform.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      # The standalone CLI works without launching the GUI app, which can
      # hang when invoked from an unregistered Nix-store app bundle on macOS.
      [pkgs.tailscale]
      ++ lib.lists.optionals hostPlatform.isLinux [pkgs.mullvad]
      ++ lib.lists.optionals hostPlatform.isDarwin [mullvadCliWrapper];
  };
}
