{
  self,
  pkgs,
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf mkAfter;
in {
  programs.fish.loginShellInit = mkIf (config.programs.fastfetch.enable && config.programs.fish.enable) (mkAfter ''
    test "$TERM_PROGRAM" = "WezTerm"; and fastfetch
  '');

  programs.fastfetch = {
    enable = true;
    package = pkgs.fastfetch;

    settings = {
      logo = {
        type = "iterm";
        source = self + "/assets/qezta.png";
        height = 20;
        width = 40;
        preserveAspectRatio = true; #iterm only
      };
      display = {
        pipe = false;
        hideCursor = false;
        separator = " -➜❯ ";
        brightColor = true;
        constants = [
          "───────────────────----────────"
        ];
        color = {
          keys = "light_magenta";
          separator = "light_white";
          title = "white";
          output = "light_white";
        };
        key = {
          type = "both";
          paddingLeft = 0;
        };
        size = {
          binaryPrefix = "iec";
          ndigits = 2;
        };
        temp = {
          unit = "C";
          ndigits = 0;
        };
        percent = {
          type = 9;
          ndigits = 0;
        };
        freq = {
          ndigits = 2;
        };
      };

      modules = [
        {
          type = "Custom";
          format = "┌{$1}─────{$1}┐";
        }
        {
          type = "OS";
          keyColor = "light_blue";
        }
        {
          type = "Kernel";
          keyColor = "light_blue";
        }
        # {
        #   type = "Display";
        #   key = "Resolution";
        #   keyColor = "light_blue";
        # }
        {
          type = "Terminal";
          keyColor = "light_green";
        }
        {
          type = "TerminalFont";
          key = "Font";
          keyColor = "light_green";
        }
        {
          type = "CPU";
          temp = true;
          keyColor = "light_red";
          format = "{1} @ {#4;35}{8}{#}";
        }
        {
          type = "processes";
          keyColor = "light_red";
        }
        {
          type = "GPU";
          temp = true;
          keyColor = "light_magenta";
          format = "{2} @ {#4;35}{4}{#}";
        }
        {
          type = "Memory";
          key = "RAM";
          keyColor = "light_yellow";
        }
        {
          type = "Swap";
          keyColor = "light_yellow";
        }
        {
          type = "LocalIP";
          keyColor = "light_cyan";
        }
        {
          type = "Custom";
          format = "└{$1}─────{$1}┘";
        }
        {
          type = "Custom";
          format = "The Qezta torus logo™, including its animated version, is a trademark of Qezta.";
        }
      ];
    };
  };
}
