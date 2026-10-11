{
  pkgs,
  config,
  ...
}: let
  c = config.lib.stylix.colors.withHashtag;
in {
  programs.television = {
    enable = true;
    # Wrap television to use bash as default shell for shell-specific commands
    package = pkgs.symlinkJoin {
      name = "television-wrapped";
      paths = [pkgs.television];
      buildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/tv \
          --set SHELL ${pkgs.bash}/bin/bash
      '';
    };
    # Disable all shell integrations to avoid keybinding conflicts with atuin (ctrl-r) and file completion (ctrl+t)
    enableBashIntegration = false;
    enableZshIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;

    settings.ui.theme = "noctalia-cyberpunk";

    themes.noctalia-cyberpunk = {
      border_fg = c.base03;
      text_fg = c.base05;
      dimmed_text_fg = c.base03;
      input_text_fg = c.base0C;
      result_count_fg = c.base09;
      result_name_fg = c.base0D;
      result_line_number_fg = c.base03;
      result_value_fg = c.base05;
      selection_fg = c.base07;
      selection_bg = c.base02;
      match_fg = c.base0B;
      preview_title_fg = c.base0C;
      channel_mode_fg = c.base00;
      channel_mode_bg = c.base0B;
      remote_control_mode_fg = c.base00;
      remote_control_mode_bg = c.base0A;
      action_picker_mode_fg = c.base00;
      action_picker_mode_bg = c.base0F;
      send_to_channel_mode_fg = c.base0C;
    };

    channels = {
      brew = {
        metadata = {
          name = "brew";
          description = "Search and preview Homebrew packages";
          requirements = ["brew" "jq"];
        };
        source.command = "(brew formulae; brew casks) | sort";
        preview = {
          command = ''
            brew info --json=v2 '{0}' | jq -r '
              if (.casks | length) > 0 then
                .casks[0] | "\u001b[1;36m# \(.token):\(.version)\u001b[0m\n\(.desc // "")\n\u001b[1mType:\u001b[0m Cask\n\u001b[1mStatus:\u001b[0m \(if .installed then "Installed" else "Not installed" end)"
              else
                .formulae[0] | "\u001b[1;36m# \(.name):\(.versions.stable)\u001b[0m\n\(.desc // "")\n\u001b[1mType:\u001b[0m Formula\n\u001b[1mStatus:\u001b[0m \(if (.installed | length) > 0 then "Installed" else "Not installed" end)"
              end
            '
          '';
          ansi = true;
        };
        keybindings.enter = "actions:open";
        actions.open = {
          description = "Open the selected package's homepage";
          command = "brew home '{0}'";
          mode = "execute";
        };
      };

      npm = {
        metadata = {
          name = "npm";
          description = "Search and preview npm registry packages";
          requirements = ["curl" "jq"];
        };
        source.command = "for i in 0 250 500 750 1000 1250 1500 1750 2000; do curl -s \"https://registry.npmjs.org/-/v1/search?size=250&from=$i&popularity=1.0\"; done | jq -rs '[.[]?.objects[]?.package.name // empty] | unique | .[]' | sort";
        preview = {
          command = ''
            npm view '{0}' --json 2>/dev/null | jq -r '"\u001b[1;36m# \(.name):\(.version)\u001b[0m\n\(.description // "")\n\n\u001b[1mHomepage:\u001b[0m \(.homepage // "N/A")\n\u001b[1mLicense:\u001b[0m \(.license // "N/A")\n\u001b[1mKeywords:\u001b[0m \((.keywords // []) | join(", "))"'
          '';
          ansi = true;
        };
        keybindings.enter = "actions:open";
        actions.open = {
          description = "Open the selected package's homepage";
          command = "npm view '{0}' homepage | xargs open";
          mode = "execute";
        };
      };

      pip = {
        metadata = {
          name = "pip";
          description = "Search and preview PyPI packages";
          requirements = ["curl" "jq"];
        };
        source.command = "curl -s 'https://hugovk.github.io/top-pypi-packages/top-pypi-packages-30-days.min.json' | jq -r '.rows[].project' | head -500";
        preview = {
          command = ''
            curl -s "https://pypi.org/pypi/{0}/json" | jq -r '"\u001b[1;36m# \(.info.name):\(.info.version)\u001b[0m\n\(.info.summary // "")\n\n\u001b[1mAuthor:\u001b[0m \(.info.author // "N/A")\n\u001b[1mLicense:\u001b[0m \(.info.license // "N/A")\n\u001b[1mHomepage:\u001b[0m \(.info.home_page // .info.project_url // "N/A")"'
          '';
          ansi = true;
        };
        keybindings.enter = "actions:open";
        actions.open = {
          description = "Open the selected package on PyPI";
          command = "open 'https://pypi.org/project/{0}/'";
          mode = "execute";
        };
      };
    };
  };
}
