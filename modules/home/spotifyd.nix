{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  tomlFormat = pkgs.formats.toml {};
  configFile = tomlFormat.generate "spotifyd.toml" cfg.settings;
  cfg = config.programs.spotifyd;
in {
  options = let
    inherit (lib) mkOption mkEnableOption mkPackageOption;
  in {
    programs.spotifyd = {
      enable = mkEnableOption "spotifyd";
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
    home.packages = mkIf (cfg.package != null) [cfg.package];
    xdg.configFile."spotifyd/spotifyd.toml".source = configFile;
  };
}
