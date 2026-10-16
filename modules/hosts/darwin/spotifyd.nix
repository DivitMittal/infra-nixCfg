{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  tomlFormat = pkgs.formats.toml {};
  configFile = tomlFormat.generate "spotifyd.toml" cfg.settings;
  cfg = config.services.spotify-daemon;
in {
  options = let
    inherit (lib) mkOption mkEnableOption mkPackageOption;
  in {
    services.spotify-daemon = {
      enable = mkEnableOption "spotify-daemon";
      package = mkPackageOption pkgs "spotifyd" {nullable = true;};
      settings = mkOption {
        inherit (tomlFormat) type;
        default = {};
        description = "Configuration for spotifyd";
        example = lib.literalExpression ''
          {
            global = {
              username = "Alex";
              password = "foo";
              device_name = "nix";
            };
          }
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    launchd.user.agents.spotify-daemon = {
      script = "${lib.getExe cfg.package} --no-daemon --config-path ${configFile}";
      serviceConfig = {
        RunAtLoad = true;
        Nice = 10;
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
      };
    };
  };
}
