{
  pkgs,
  lib,
  inputs,
  hostPlatform,
  ...
}: let
  configFile = inputs.TLTR + "/kanata/tltr.kbd";
in {
  imports = [inputs.kanata-tray.homeManagerModules.kanata-tray];

  home.packages =
    [pkgs.kanata-with-cmd]
    # Launch helper for kanata-tray + the Karabiner VirtualHID daemon (macOS only).
    ++ lib.optional hostPlatform.isDarwin pkgs.customDarwin.kanata-tray-daemon;

  programs.kanata-tray = {
    enable = true;

    settings = {
      general = {
        allow_concurrent_presets = false;
      };
      defaults = {
        kanata_executable = "${pkgs.kanata-with-cmd}/bin/kanata";
        tcp_port = 5830;
      };
      presets = {
        TLTR = {
          kanata_config = "${configFile}";
          autorun = true;
          extra_args = ["--nodelay"];
        };
      };
    };
  };
}
