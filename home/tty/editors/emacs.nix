{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption;
  cfg = config.programs.doom-emacs;
in {
  imports = [inputs.nix-doom-emacs-unstraightened.homeModule];

  options.programs.doom-emacs = {
    # The nix-doom-emacs-unstraightened homeModule and the xdg.configFile
    # symlink below both target ~/.config/doom — pick exactly one.
    mode = mkOption {
      type = lib.types.enum ["module" "symlink"];
      default = "module";
      description = ''
        How to wire up Doom Emacs. `module` enables the
        nix-doom-emacs-unstraightened homeModule, which installs Doom and
        pins Emacs for you. `symlink` only links ~/.config/doom to
        inputs.Emacs-Cfg, leaving installation and Emacs selection up to
        something else.
      '';
    };
  };

  config = {
    programs.doom-emacs = {
      # In `symlink` mode the module is dormant — no install, no doomDir
      # write — so it doesn't fight the xdg.configFile symlink below.
      enable = cfg.mode == "module";
      doomDir = inputs.Emacs-Cfg;
      emacs = pkgs.emacs-nox;
    };

    # nix-doom-emacs-unstraightened brings its own emacs in `module` mode;
    # in `symlink` mode we're on our own, so install emacs ourselves.
    programs.emacs = mkIf (cfg.mode == "symlink") {
      enable = true;
      package = pkgs.emacs-nox;
    };

    # Doom's :checkers spell module needs a spell-checker binary on PATH in
    # either mode; without one flyspell errors in every text buffer.
    home.packages = [(pkgs.aspellWithDicts (d: [d.en]))];

    xdg.configFile."doom" = mkIf (cfg.mode == "symlink") {
      enable = true;
      source = inputs.Emacs-Cfg;
      recursive = true;
    };
  };
}
