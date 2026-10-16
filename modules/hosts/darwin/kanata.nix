{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.services.kanata;
  karabinerDaemon = "/Library/Application\\ Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon";
  configFile = pkgs.writeText "kanata.kbd" cfg.config;
  command = [(lib.getExe cfg.package) "--nodelay"] ++ lib.lists.optionals (cfg.config != "") ["--cfg" configFile];
in {
  options = let
    inherit (lib) mkOption mkPackageOption mkEnableOption types;
  in {
    services.kanata = {
      enable = mkEnableOption "kanata";
      package = mkPackageOption pkgs "kanata" {nullable = true;};
      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        example = lib.literalExpression ''
          {
            ENV_VAR1 = "value1";
          }
        '';
        description = "Environment variables to be set for kanata-tray & kanata";
      };
      config = mkOption {
        type = types.str;
        default = "";
        example = lib.literalExpression ''
          (defsrc
            caps grv         i
                        j    k    l
            lsft rsft
          )

          (deflayer default
            @cap @grv        _
                        _    _    _
            _    _
          )

          (defalias
            cap (tap-hold-press 200 200 caps lctl)
            grv (tap-hold-press 200 200 grv (layer-toggle arrows))
          )
        '';
        description = ''
          Your kanata configuration in the kanata lisp-like configuration language
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    launchd.daemons.kanata = {
      script = "sudo --preserve-env " + "${lib.strings.concatStringsSep " " command}";
      serviceConfig = {
        EnvironmentVariables = cfg.environment;
        StandardOutPath = /tmp/org.nixos.kanata.out.log;
        StandardErrorPath = /tmp/org.nixos.kanata.err.log;
        RunAtLoad = true;
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
        Nice = -19;
      };
    };

    launchd.daemons.karabiner-daemon = {
      script = "sudo " + karabinerDaemon;
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
        Nice = -19;
      };
    };

    # security.sudo.extraConfig = ''
    #   ALL ALL=(ALL) NOPASSWD: ${lib.strings.concatStringsSep " " command}
    # '';
    environment.etc."sudoers.d/kanata".source = pkgs.runCommand "sudoers-kanata" {} ''
      cat <<EOF >"$out"
      ALL ALL=(ALL) NOPASSWD:SETENV: ${lib.strings.concatStringsSep " " command}
      ALL ALL=(ALL) NOPASSWD: ${karabinerDaemon}
      EOF
    '';
  };
}
