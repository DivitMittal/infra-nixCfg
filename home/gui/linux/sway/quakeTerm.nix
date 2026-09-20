# Quake-style dropdown WezTerm: Mod+grave toggles a WezTerm window living in
# the "quake" workspace (term-nixCfg/emulators/wezterm/quakeTerm.lua tags it
# with a stable title, mirroring the macOS Hammerspoon toggle in the
# hammerspoon-nix repo) in and out of Sway's scratchpad.
#
# The window.commands rule below fires the moment a window with this app_id
# first appears: it floats, sizes, and immediately shows it from the
# scratchpad, so the very first press already drops the terminal in instead
# of just opening a bare window. Every press after that just asks Sway to
# toggle the same instance via `scratchpad show` — the toggle script only
# falls back to spawning a fresh WezTerm process when no such window exists
# yet (e.g. after it's been closed).
{
  pkgs,
  lib,
  ...
}: let
  mod = "Mod4";
  appId = "wezterm-quake";
  toggle = pkgs.writeShellScriptBin "quake-term-toggle" ''
    set -euo pipefail
    if ${pkgs.sway}/bin/swaymsg -t get_tree \
      | ${pkgs.jq}/bin/jq -e '.. | objects | select(.app_id? == "${appId}")' >/dev/null 2>&1; then
      ${pkgs.sway}/bin/swaymsg '[app_id="${appId}"] scratchpad show'
    else
      exec ${pkgs.wezterm}/bin/wezterm start --domain local-mux --attach --workspace quake --class ${appId}
    fi
  '';
in {
  home.packages = [toggle];

  wayland.windowManager.sway.config = {
    window.commands = [
      {
        criteria.app_id = appId;
        command = "floating enable, resize set 100 ppt 45 ppt, move position 0 0, move scratchpad, scratchpad show";
      }
    ];

    keybindings = lib.mkOptionDefault {
      "${mod}+grave" = "exec ${toggle}/bin/quake-term-toggle";
    };
  };
}
