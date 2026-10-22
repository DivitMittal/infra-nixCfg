{
  pkgs,
  config,
  lib,
  ...
}: let
  eza_opts = lib.strings.concatStringsSep " " config.programs.eza.extraOptions;
  fd_opts = lib.strings.concatStringsSep " " ["--hidden"];
  delta_opts = lib.strings.concatStringsSep " " ["--paging=never"];
  inherit (lib) mkIf;
in {
  programs.fzf = {
    enable = true;
    package = pkgs.fzf;

    enableFishIntegration = false;
    enableZshIntegration = false;
    enableBashIntegration = false;
    # home-manager asserts fzf >= 0.73 for nushell; Nixpkgs 26.05 (x86_64-darwin) ships 0.72
    enableNushellIntegration = lib.versionAtLeast config.programs.fzf.package.version "0.73.0";

    defaultCommand = "${pkgs.fd}/bin/fd ${fd_opts}";

    defaultOptions = [
      "--multi"
      "--cycle"
      "--border"
      "--height 50%"
      "--bind='right:select'"
      "--bind='left:deselect'"
      "--bind='tab:down'"
      "--bind='btab:up'"
      "--no-scrollbar"
      "--marker='*'"
      "--preview-window=wrap"
    ];
  };

  programs.fish = mkIf config.programs.fish.enable {
    plugins = [
      {
        name = "fzf";
        src = pkgs.fetchFromGitHub {
          owner = "PatrickF1";
          repo = "fzf.fish";
          rev = "main";
          hash = "sha256-H7HgYT+okuVXo2SinrSs+hxAKCn4Q4su7oMbebKd/7s=";
        };
      }
    ];

    interactiveShellInit = ''
      ## PatrickF1/fzf.fish plugin
      fzf_configure_bindings --variables=\ev --processes=\ep --git_status=\es --git_log=\el --history=\er --directory=\ef
      set -gx fzf_fd_opts ${fd_opts}
      set -gx fzf_preview_dir_cmd ${pkgs.eza}/bin/eza ${eza_opts}
      set -gx fzf_preview_file_cmd ${pkgs.bat}/bin/bat
      set -gx fzf_diff_highlighter ${pkgs.delta}/bin/delta ${delta_opts}
    '';
  };
}
