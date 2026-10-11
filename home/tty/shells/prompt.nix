{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (lib) mkAfter mkIf;
in {
  programs.bash = mkIf config.programs.bash.enable {
    initExtra = mkAfter ''
      if [ "`id -u`" -eq 0 ]; then # ckeck for root user
        PS1="\[\e[1;31m\]\u\[\e[1;36m\]\[\033[m\]@\[\e[1;36m\]\h\[\033[m\]:\[\e[0m\]\[\e[1;32m\][\w]> \[\e[0m\]"
      else
        PS1="\[\e[1m\]\u\[\e[1;36m\]\[\033[m\]@\[\e[1;36m\]\h\[\033[m\]:\[\e[0m\]\[\e[1;32m\][\w]> \[\e[0m\]"
      fi
    '';
  };

  programs.zsh = mkIf config.programs.zsh.enable {
    initContent = mkAfter "PS1='%F{cyan}%~%f %# '";
  };

  home.sessionVariables = {
    STARSHIP_LOG = "error";
  };

  programs.starship = {
    enable = true;
    package = pkgs.starship;

    enableFishIntegration = config.programs.fish.enable;
    enableZshIntegration = false;
    enableBashIntegration = false;
    enableNushellIntegration = config.programs.nushell.enable;
    enableInteractive = true;

    settings = {
      format = lib.strings.concatStrings [
        "[╭─env─-➜❯](bold blue) "
        "$sudo"
        "$username"
        "$hostname"
        "$shell"
        "\${custom.yazi}"
        "$status"
        "$custom"
        "$cmd_duration"
        "$docker_context"
        "$directory"
        "$git_branch"
        "$git_commit"
        "$git_status"
        "\n"
        # "[┣─pwd─-➜❯](bold red) "  "$directory" "$git_branch" "$git_commit" "$git_status" "\n"
        "[╰─cmd─➜❯](bold green) "
        "$character"
      ];
      right_format = lib.strings.concatStrings [
        "$direnv"
        "$nix_shell"
        "$lua"
        "$rust"
        "$java"
        "$kotlin"
        "$dart"
        "$python"
        "$golang"
        "$swift"
        "$nodejs"
        "$php"
        "$conda"
        "$package"
      ];

      add_newline = true;
      command_timeout = 425;
      scan_timeout = 50; # scaning files in the current directory
      follow_symlinks = true;

      character = {
        disabled = false;
        format = "$symbol ";
        error_symbol = "[✗](bold red)";
        success_symbol = "[➜](bold green)";
        vicmd_symbol = "[V](bold blue)";
      };
      username = {
        disabled = false;
        show_always = true;
        format = "[$user]($style)";
        style_root = "red bold";
        style_user = "italic bright-purple";
      };
      hostname = {
        disabled = false;
        format = "[@](bold blue)[$hostname]($style) ";
        style = "bold red";
        ssh_only = false;
        trim_at = ".";
      };
      direnv = {
        disabled = false;
        symbol = "with 📂env: ";
        format = "[$symbol$loaded/$allowed]($style) ";
        style = "orange";
      };
      directory = {
        disabled = false;
        home_symbol = "🏡";
        format = "at [$path]($style)[$read_only]($read_only_style) ";
        style = "cyan";
        truncate_to_repo = false;
        truncation_length = 10;
        truncation_symbol = "…/";
      };
      cmd_duration = {
        disabled = false;
        format = "took [$duration]($style) ";
        style = "bold yellow";
        show_milliseconds = true;
      };
      package = {
        disabled = false;
        format = "[🎁 $version]($sytle) ";
        style = "208 bold";
      };
      shell = {
        disabled = false;
        format = "via $indicator ";
        bash_indicator = "🐑";
        fish_indicator = "🐠";
        nu_indicator = "🦬";
        powershell_indicator = "_";
        unknown_indicator = "❓";
        zsh_indicator = "🦓";
      };
      status = {
        disabled = true;
        format = "[\\[$symbol$status\\]]($style) ";
        symbol = "💥 ";
        style = "red";
      };
      sudo = {
        disabled = false;
        format = " [$symbol]($style)";
        symbol = "🧙";
        style = "bold green";
      };
      git_branch = {
        disabled = false;
        always_show_remote = true;
        format = "on 🌱:[$branch]($style) 🎋:[$remote_name/$remote_branch]($style) ";
        style = "bold yellow";
      };
      git_commit = {
        disabled = true;
        only_detached = false;
        style = "red";
        tag_disabled = false;
      };
      git_status = {
        disabled = false;
        ahead = "🏃\\([$count]($style)\\)";
        behind = "🐌\\([$count]($style)\\)";
        conflicted = "🤔";
        deleted = "🚮";
        diverged = "😵\\(\\(🏃[$ahead_count]($style)\\);🐌\\([$behind_count]($style)\\)\\)";
        modified = "📝";
        renamed = "🐣";
        staged = "🎤\\([$count]($style)\\)";
        stashed = "📦";
        untracked = "🙈";
        style = "bold blue";
      };

      ## External
      swift = {disabled = false;};
      rust = {disabled = false;};
      php = {disabled = false;};
      python = {disabled = false;};
      nodejs = {disabled = false;};
      java = {disabled = false;};
      kotlin = {disabled = false;};
      lua = {disabled = false;};
      golang = {disabled = false;};
      dart = {disabled = false;};
      nix_shell = {
        disabled = false;
        format = "via [❄️ $state( \\($name\\))](bold blue) ";
        impure_msg = "[impure shell](bold red)";
        pure_msg = "[pure shell](bold green)";
        unknown_msg = "[unknown shell](bold yellow)";
      };

      custom.yazi = {
        disabled = false;
        when = ''test -n "$YAZI_LEVEL"'';
        description = "Indicate the shell was launched by `yazi`";
        symbol = "on 🦆 ";
      };

      ## Disabled
      battery = {
        disabled = true;
        format = "🔋:$symbol ";
        charging_symbol = "⚡️";
        discharging_symbol = "💦";
        display = [{threshold = 100;}];
        full_symbol = "💪";
        unknown_symbol = "💡";
      };

      time = {
        disabled = true;
        format = "@ ⏰:[\\[$time\\]](bold yellow) ";
        use_12hr = true;
      };

      docker_context = {disabled = true;};

      custom.docker = {
        disabled = true;
        description = "Shows a  docker symbol if the current directory has Dockerfile or docker-compose.yml files";
        files = ["Dockerfile" "docker-compose.yml" "docker-compose.yaml"];
        format = "with $symbol ";
        symbol = "🐳";
      };

      conda = {
        disabled = true;
        format = "in [$symbol$environment]($style) ";
        style = "dimmed green";
        ignore_base = true;
      };
    };
  };
}
