{
  pkgs,
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf;

  git-pull-all = pkgs.writeShellApplication {
    name = "git-pull-all";
    runtimeInputs = with pkgs; [fd git gnused gnugrep coreutils];
    # Kept as a standalone .sh so it's lintable on its own and free of Nix
    # ''-string escaping; writeShellApplication still shellchecks it at build.
    text = builtins.readFile ./git-pull-all.sh;
  };
in {
  home.packages = mkIf config.programs.git.enable [
    git-pull-all
  ];
}
