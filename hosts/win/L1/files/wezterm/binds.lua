-- WezTerm keybindings
local wezterm = require("wezterm")
local act     = wezterm.action
local M       = {}

function M.apply(config)
  config.leader = { key = "r", mods = "CTRL", timeout_milliseconds = 800 }

  config.disable_default_key_bindings = false

  config.keys = {
    -- Shift+Enter → ESC+Enter (useful in vi-mode terminals like Neovim)
    { key = "Enter", mods = "SHIFT",
      action = act.SendKey { key = "Enter", mods = "ALT" } },

    -- Disable Alt+Enter (usually triggers fullscreen in other apps)
    { key = "Enter", mods = "ALT", action = act.DisableDefaultAssignment },

    -- ── Pane management (Leader + key) ──────────────────────────────────
    { key = "s", mods = "LEADER",
      action = act.SplitVertical { domain = "CurrentPaneDomain" } },

    { key = "v", mods = "LEADER",
      action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },

    { key = "5", mods = "LEADER",
      action = act.TogglePaneZoomState },

    { key = "Space", mods = "LEADER",
      action = act.RotatePanes "Clockwise" },

    { key = "f", mods = "LEADER",
      action = act.Search { CaseSensitiveString = "" } },

    { key = "Enter", mods = "LEADER",
      action = act.ActivateCopyMode },

    -- ── Tab management ───────────────────────────────────────────────────
    { key = "t", mods = "LEADER",
      action = act.SpawnTab "CurrentPaneDomain" },

    { key = "w", mods = "LEADER",
      action = act.CloseCurrentTab { confirm = true } },

    -- ── Smart Splits (see smartSplits.lua) ──────────────────────────────
    { key = "h", mods = "CTRL",
      action = act.EmitEvent "ActivatePaneDirection-left" },
    { key = "l", mods = "CTRL",
      action = act.EmitEvent "ActivatePaneDirection-right" },
    { key = "k", mods = "CTRL",
      action = act.EmitEvent "ActivatePaneDirection-up" },
    { key = "j", mods = "CTRL",
      action = act.EmitEvent "ActivatePaneDirection-down" },
  }
end

return M
