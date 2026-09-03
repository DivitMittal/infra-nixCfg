{
  lib,
  pkgs,
  ...
}: let
  toolkits = import ./_toolkits.nix;
  # A Neovim distro compiles treesitter grammars on first launch, so the editor
  # toolkit cannot stand without a compiler.
  wantBuild = toolkits.build || toolkits.editor;

  basePackages = with pkgs; [ncurses];
  shellPackages = with pkgs; [fish eza zoxide yazi fd ripgrep fzf];
  eyeCandyPackages = with pkgs; [fastfetch timg chafa];
  editorPackages = with pkgs; [neovim tree-sitter lazygit python3 imagemagick];
  buildPackages = with pkgs; [gcc gnumake cmake pkg-config binutils autoconf automake libtool patch gettext file unzip gnutar gzip xz];
  nodePackages = with pkgs; [nodejs];
  goPackages = with pkgs; [go];
  pythonPackages = with pkgs; [python3 uv];
in {
  home.packages =
    basePackages
    ++ lib.optionals toolkits.shell shellPackages
    ++ lib.optionals toolkits.eyeCandy eyeCandyPackages
    ++ lib.optionals toolkits.editor editorPackages
    ++ lib.optionals wantBuild buildPackages
    ++ lib.optionals toolkits.node nodePackages
    ++ lib.optionals toolkits.go goPackages
    ++ lib.optionals toolkits.python pythonPackages;

  programs.fish.enable = toolkits.shell;

  # `gx` in neovim, and anything else shelling out to xdg-open, has no handler
  # inside the proot; hand it to Android's own opener via termux-open.
  home.file.".local/bin/xdg-open" = {
    executable = true;
    text = ''
      #!/bin/sh
      exec termux-open "$@"
    '';
  };

  home.sessionVariables =
    {
      EDITOR = "nvim";
      PAGER = "less";
      # Nothing in the bootstrap sets a locale, so glibc falls back to "C" and
      # UTF-8 box-drawing/prompt glyphs misrender everywhere. C.UTF-8 needs no
      # locale archive.
      LANG = "C.UTF-8";
    }
    // lib.optionalAttrs toolkits.node {
      # npm's default prefix is the nix profile, a read-only store path.
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    }
    // lib.optionalAttrs toolkits.go {
      GOPATH = "$HOME/go";
      GOBIN = "$HOME/go/bin";
    }
    // lib.optionalAttrs toolkits.python {
      # uv's own python-build-standalone downloads expect a distro loader
      # (/lib/ld-linux-aarch64.so.1) that doesn't exist inside the proot;
      # point uv at the nix python3 instead.
      UV_PYTHON_DOWNLOADS = "never";
      UV_PYTHON_PREFERENCE = "only-system";
    };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.npm-global/bin"
    "$HOME/go/bin"
  ];

  # home.stateVersion is set by the shared bridge, common/hosts/droid/home-manager.nix.
}
