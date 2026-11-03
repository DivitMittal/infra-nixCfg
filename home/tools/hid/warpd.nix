{
  pkgs,
  hostPlatform,
  ...
}: {
  programs.warpd = {
    enable = true;
    # customDarwin.warpd is the macOS build; nixpkgs' warpd covers Linux.
    package =
      if hostPlatform.isDarwin
      then pkgs.customDarwin.warpd
      else pkgs.warpd;
    settings = {
      ## Normal mode movement
      left = "n";
      down = "e";
      up = "u";
      right = "i";

      ## Speed
      speed = 220;
      max_speed = 1600;
      acceleration = 700;
      decelerator_speed = 50;

      ## Scrolling (capitalised counterparts of the movement keys)
      scroll_down = "m";
      scroll_up = "j";
      scroll_left = "J";
      scroll_right = "M";

      ## Cursor appearance
      cursor_color = "#ff0000";
      cursor_size = 7;
      indicator = "topright";
      indicator_color = "#ff0000";
      indicator_size = 12;

      ## Mouse buttons (t=left, comma=middle, g=right)
      buttons = "t , g";

      ## Global actions (prepend: Alt+Meta)
      hint = "x"; # activate hint
      smart_hint = "f"; # smart/element-based hints
      hint2 = "X"; # two-pass hint
      grid = "g";
      screen = "s";
      normal = "q";
      history = ";";

      ## In-normal-mode actions (defaults kept unless they conflict)
      # drag = "v";          ## visual mode
      # copy = "y";
      # copy_and_exit = "c";
      # paste = "p";
      # accelerator = "a";
      # decelerator = "d";

      ### Grid configuration
      ## Grid mode (2×2)
      grid_nr = 2;
      grid_nc = 2;
      ## Navigation
      grid_left = "n";
      grid_down = "e";
      grid_up = "u";
      grid_right = "i";
      grid_cut_left = "N";
      grid_cut_down = "E";
      grid_cut_up = "U";
      grid_cut_right = "I";
      ## reading order: top-left, top-right, bottom-left, bottom-right
      grid_keys = "q w a r";

      ### Hint configuration
      ## Colemak home-row biased character set
      hint_chars = "arstneidhopgwyf";
      hint_bgcolor = "#000000";
      hint_fgcolor = "#00ff00";
      hint_size = 20;
      ## Two-shot hint mode (≥ hint2_grid_size² = 9 chars required)
      hint2_chars = "arstneiodhpgwyfbvcxzqjklm";
      hint2_gap_size = 5;
      hint2_grid_size = 3;
      ## Screen selection (Colemak home row)
      screen_chars = "arstdhneio";
      ## Smart hint mode
      smart_hint_mode = "alphabet";
    };
  };
}
