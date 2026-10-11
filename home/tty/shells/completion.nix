{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (lib) mkIf mkMerge;
in {
  home.sessionVariables = mkIf config.programs.carapace.enable {
    CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense";
    CARAPACE_MATCH = "1"; # Case-insensitive matching
    CARAPACE_LENIENT = "1"; # Allow unknown flags
    # CARAPACE_EXCLUDES = "";       # Exclude specific completers (e.g., "git,docker")
  };

  programs.bash = mkIf config.programs.bash.enable {
    enableCompletion = true;
  };

  programs.zsh = mkIf config.programs.zsh.enable {
    enableCompletion = true;

    antidote.plugins = mkMerge [
      [
        "zsh-users/zsh-completions path:src kind:fpath"
      ]
      (mkIf config.programs.fzf.enable [
        "Aloxaf/fzf-tab"
      ])
    ];

    initContent = mkMerge [
      (mkIf config.programs.carapace.enable ''
        # Zsh-specific carapace configuration
        export CARAPACE_MERGEFLAGS=1      # Merge flags to single tag group (zsh default)

        # Zsh completion styling (works with carapace)
        zstyle ':completion:*' menu select
        zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
        zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
      '')
    ];
  };

  programs.fish = mkIf config.programs.fish.enable {
    generateCompletions = true;

    plugins = mkIf config.programs.fzf.enable [
      {
        name = "fifc";
        src = pkgs.fetchFromGitHub {
          owner = "gazorby";
          repo = "fifc";
          rev = "main";
          hash = "sha256-Ynb0Yd5EMoz7tXwqF8NNKqCGbzTZn/CwLsZRQXIAVp4=";
        };
      }
    ];

    interactiveShellInit = mkIf config.programs.fzf.enable ''
      ## fifc plugin - Fish Interactive File Completion
      set -gx fifc_editor ${config.home.sessionVariables.VISUAL}
      set -gx fifc_fd_opts --hidden
      set -gx fifc_eza_opts ${lib.strings.concatStringsSep " " config.programs.eza.extraOptions}
    '';
  };

  programs.carapace = {
    enable = true;
    package = pkgs.carapace;

    enableBashIntegration = false;
    enableZshIntegration = config.programs.zsh.enable;
    enableFishIntegration = config.programs.fish.enable;
    enableNushellIntegration = config.programs.nushell.enable;
  };
}
