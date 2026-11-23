{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.warpd;

  # Format warpd config as key: value pairs
  formatConfig = settings:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "${name}: ${toString value}") settings
    );
in {
  options.programs.warpd = {
    enable = mkEnableOption "warpd, a modal keyboard-driven virtual pointer";

    package = mkPackageOption pkgs "warpd" {nullable = true;};

    settings = mkOption {
      type = types.attrsOf (types.oneOf [types.str types.int types.bool]);
      default = {};
      example = literalExpression ''
        {
          activation_key = "M-m";
          hint_mode = "M-x";
          grid_mode = "M-g";
          normal_mode = "M-c";
          left = "h";
          down = "j";
          up = "k";
          right = "l";
        }
      '';
      description = ''
        Configuration options for warpd.
        See warpd(1) for available options.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = mkIf (cfg.package != null) [cfg.package];

    xdg.configFile."warpd/config" = mkIf (cfg.settings != {}) {
      text = formatConfig cfg.settings;
    };
  };
}
