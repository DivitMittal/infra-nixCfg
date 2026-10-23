# Source-of-truth visual identity for infra-nixCfg.
#
# A custom base16 scheme: cyberpunk neon accents on pure pitch-black background.
# Originally derived from the (now-removed) noctalia palette, with the background
# hardened from its deep navy (#0d0d1a) to true #000000.
# Semi-transparency is delegated to the terminal via stylix.opacity.terminal so
# the underlying wallpaper / blur shows through.
#
# Consumed by:
#   - common/home/stylix.nix           (home-manager)
#   - common/hosts/nixos/stylix.nix    (NixOS system)
#   - common/hosts/darwin/stylix.nix   (nix-darwin)
{pkgs}: rec {
  # 16-color base16 palette.
  # base08–0F follow base16 conventions:
  #   08 red · 09 orange · 0A yellow · 0B green · 0C cyan · 0D blue · 0E magenta · 0F violet
  base16Scheme = {
    base00 = "000000"; # bg                pitch black
    base01 = "0a0a14"; # lighter bg        near-black surface
    base02 = "1a1a2e"; # selection bg      noctalia surfaceVariant
    base03 = "5a5a8a"; # comments / dim fg muted indigo
    base04 = "a0a0d0"; # dark fg           line numbers / status bar
    base05 = "e0e0ff"; # default fg        noctalia onSurface (soft white-blue)
    base06 = "f0f0ff"; # light fg          highlights
    base07 = "ffffff"; # lightest fg       cursor / inverse
    base08 = "ff3355"; # red               errors / deletions
    base09 = "ff8800"; # orange            constants / booleans
    base0A = "ffee00"; # yellow            classes / warnings
    base0B = "00ff88"; # green             strings / inserts        cyberpunk lime
    base0C = "00ffe7"; # cyan              regex / quotes           noctalia mPrimary
    base0D = "00aaff"; # blue              functions / methods
    base0E = "ff2d78"; # magenta           keywords / itals         noctalia onSurfaceVariant
    base0F = "b266ff"; # violet            deprecated / embedded
  };

  # Stylix opacity controls (0 = fully transparent, 1 = opaque).
  # Terminal at 0.85 keeps glyphs crisp while letting the wallpaper bleed
  # through enough to read as "semi-transparent pitch black".
  opacity = {
    applications = 1.0;
    desktop = 1.0;
    popups = 0.92;
    terminal = 0.85;
  };

  # Font stack — CaskaydiaCove Nerd Font is already the system font
  # (common/hosts/all/misc.nix, common/hosts/droid/termux.nix).
  fonts = {
    monospace = {
      package = pkgs.nerd-fonts.caskaydia-cove;
      name = "CaskaydiaCove Nerd Font Mono";
    };
    sansSerif = {
      package = pkgs.dejavu_fonts;
      name = "DejaVu Sans";
    };
    serif = {
      package = pkgs.dejavu_fonts;
      name = "DejaVu Serif";
    };
    emoji = {
      package = pkgs.noto-fonts-color-emoji;
      name = "Noto Color Emoji";
    };
    sizes = {
      terminal = 13;
      applications = 12;
      desktop = 11;
      popups = 11;
    };
  };

  # Pitch-black wallpaper (assets/pitch-black.png is a 2560x1440 #000000 PNG).
  wallpaper = ../assets/pitch-black.png;

  polarity = "dark";
}
