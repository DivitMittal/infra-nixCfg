{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption;
  cfg = config.programs.nvchad;
in {
  imports = [inputs.nvchad4nix.homeManagerModule];

  options.programs.nvchad = {
    # nvchad4nix bundles its own neovim + NvChad config; programs.neovim
    # would clash with it — pick exactly one.
    mode = mkOption {
      type = lib.types.enum ["module" "stock"];
      default = "module";
      description = ''
        How to wire up Neovim. `module` enables the nvchad4nix homeModule,
        which installs NvChad and provides its wrapped neovim. `stock`
        uses plain programs.neovim (no NvChad, no nvchad4nix config).
      '';
    };
  };

  config = {
    programs.nvchad = {
      # In `stock` mode the module is dormant so it doesn't fight the
      # programs.neovim block below.
      enable = cfg.mode == "module";
      # nvchad4nix's wrapper already puts tree-sitter and a C compiler (the `gcc`
      # option) on nvim's PATH, which nvim-treesitter's main branch needs for
      # :TSInstallAll — don't duplicate them here.
      extraPackages = lib.attrsets.attrValues {
        inherit (pkgs) prettier;
        inherit
          (pkgs)
          stylua
          nixd
          alejandra
          clang-tools
          vscode-langservers-extracted
          ;
        inherit (pkgs) bash-language-server;
        inherit (pkgs) shfmt;
        python = pkgs.python3.withPackages (ps:
          with ps; [
            python-lsp-server
            flake8
            black
          ]);
      };
      backup = false;
    };

    programs.neovim = mkIf (cfg.mode == "stock") {
      enable = true;
      package = pkgs.neovim-unwrapped;
      defaultEditor = true;
    };

    programs.fish.shellAbbrs.nv = mkIf config.programs.fish.enable {
      expansion = "nvim";
      position = "command";
    };
    programs.zsh.zsh-abbr.abbreviations.nv = mkIf config.programs.zsh.enable "nvim";
  };
}
