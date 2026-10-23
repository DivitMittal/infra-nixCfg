{
  lib,
  pkgs,
  launcherTemplate,
  ...
}: let
  toolkits = import ./_toolkits.nix;
  # A Neovim distro compiles treesitter grammars on first launch, so the editor
  # toolkit cannot stand without a compiler.
  wantBuild = toolkits.build || toolkits.editor;

  # Shared tty modules from the rest of the flake. Only ones that need nothing
  # beyond pkgs/config are pulled in: the droid class doesn't load common/home or
  # pass `self`/`inputs` into home-manager.
  homeTty = ../../../home/tty;
  sharedShellModules = [
    (homeTty + "/shells/fish.nix")
    (homeTty + "/shells/prompt.nix")
    (homeTty + "/find/fzf.nix")
    (homeTty + "/atuin.nix")
  ];

  basePackages = with pkgs; [ncurses];
  shellPackages = with pkgs; [eza zoxide yazi fd ripgrep];
  eyeCandyPackages = with pkgs; [fastfetch timg chafa];
  editorPackages = with pkgs; [neovim tree-sitter lazygit python3 imagemagick];
  buildPackages = with pkgs; [gcc gnumake cmake pkg-config binutils autoconf automake libtool patch gettext file unzip gnutar gzip xz];
  nodePackages = with pkgs; [nodejs];
  goPackages = with pkgs; [go];
  pythonPackages = with pkgs; [python3 uv];
  # The launcher scans the profile for .desktop files and lists them in the drawer.
  # xterm is deliberately absent: it dies on setuid() under Android.
  guiPackages = with pkgs; [
    xkeyboard-config # the X server exits on startup without it
    openbox # started with the display automatically; title bars + move/resize
    dejavu_fonts # boxes instead of text otherwise
    xfce4-terminal
    mousepad
  ];

  # `setup-nvim`: AstroNvim/NvChad/LazyVim/kickstart chooser with OSC 52 clipboard,
  # phone-width wrap, and a colourscheme generated from the wallpaper palette.
  nvimTools = import "${launcherTemplate}/nvim-tools.nix" {inherit pkgs;};
in {
  imports = lib.optionals toolkits.shell sharedShellModules;

  home.packages =
    basePackages
    ++ lib.optionals toolkits.shell shellPackages
    ++ lib.optionals toolkits.eyeCandy eyeCandyPackages
    ++ lib.optionals toolkits.editor (editorPackages ++ nvimTools)
    ++ lib.optionals wantBuild buildPackages
    ++ lib.optionals toolkits.node nodePackages
    ++ lib.optionals toolkits.go goPackages
    ++ lib.optionals toolkits.python pythonPackages
    ++ lib.optionals toolkits.gui guiPackages;

  programs.fish = lib.mkIf toolkits.shell {
    enable = true;
    # The bits of the template's config.fish the launcher itself relies on.
    shellInit = ''
      # launcherctl and tai live in the proot's /bin, outside the generated PATH.
      # Appended so nix binaries keep priority.
      test -d /nix; and fish_add_path --global --append /bin
      fish_add_path --global "$HOME/.termux/bin"

      set -gx TMPDIR "$HOME/.tmp"
      mkdir -p "$TMPDIR"
      set -q COLORTERM; or set -gx COLORTERM truecolor
    '';
  };

  # Launcher fastfetch config: the logo is an animated GIF drawn over the kitty
  # graphics protocol, which the launcher terminal implements natively. Stock
  # fastfetch shows the first frame; the template's overlays.nix animates it but
  # has to compile on the phone (~20 min), so it isn't applied here.
  xdg.configFile."fastfetch/config.jsonc" = lib.mkIf toolkits.eyeCandy {
    source = "${launcherTemplate}/config/fastfetch/config.jsonc";
  };
  # Copied once to a writable path, so swapping in another GIF needs no switch.
  home.activation.fastfetchLogo = lib.mkIf toolkits.eyeCandy (lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -e "$HOME/Pictures/gif/skel.gif" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/Pictures/gif"
      $DRY_RUN_CMD cp ${launcherTemplate}/config/fastfetch/logo.gif "$HOME/Pictures/gif/skel.gif"
      $DRY_RUN_CMD chmod u+w "$HOME/Pictures/gif/skel.gif"
    fi
  '');

  # TLTR for the launcher's built-in keyboard; see keyboard/keymap.svg. Copied, not
  # linked: the app reads it from the Android side, where /nix/store doesn't resolve.
  # Applied on the next `termux-reload-settings` or app restart.
  home.activation.keyboardLayout = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! cmp -s ${./keyboard/layout.xml} "$HOME/.termux/keyboard/layout.xml"; then
      $DRY_RUN_CMD mkdir -p "$HOME/.termux/keyboard"
      $DRY_RUN_CMD install -m 644 ${./keyboard/layout.xml} "$HOME/.termux/keyboard/layout.xml"
    fi
  '';

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
