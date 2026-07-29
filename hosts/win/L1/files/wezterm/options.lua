-- WezTerm options — appearance and behaviour
local M = {}

function M.apply(config)
  -- ── Shell ───────────────────────────────────────────────────────────────
  config.default_prog = { "pwsh.exe", "-NoLogo" }

  -- ── Font ────────────────────────────────────────────────────────────────
  config.font = require("wezterm").font("CaskaydiaCove Nerd Font", {
    weight   = "Regular",
    italic   = false,
  })
  config.font_size           = 12.0
  config.harfbuzz_features   = { "calt=1", "clig=1", "liga=1" }  -- Enable ligatures

  -- ── Colour scheme ───────────────────────────────────────────────────────
  config.color_scheme = "Catppuccin Mocha"
  config.colors = {
    cursor_bg    = "#ff5555",
    cursor_fg    = "#282a36",
    cursor_border = "#ff5555",
  }

  -- ── Window ──────────────────────────────────────────────────────────────
  config.initial_cols          = 120
  config.initial_rows          = 30
  config.window_background_opacity = 0.92
  config.text_background_opacity   = 1.0
  config.enable_scroll_bar     = false
  config.window_padding        = { left = 4, right = 4, top = 4, bottom = 4 }
  config.window_decorations    = "RESIZE"  -- No title bar chrome
  config.window_close_confirmation = "AlwaysPrompt"

  -- ── Terminal emulation ───────────────────────────────────────────────────
  config.term               = "xterm-256color"
  config.enable_kitty_graphics = true   -- Kitty image protocol

  -- ── Tabs ─────────────────────────────────────────────────────────────────
  config.hide_tab_bar_if_only_one_tab = true
  config.use_fancy_tab_bar            = false
  config.tab_bar_at_bottom            = false

  -- ── Hyperlinks ──────────────────────────────────────────────────────────
  config.hyperlink_rules = require("wezterm").default_hyperlink_rules()
  -- GitHub shorthand: owner/repo
  table.insert(config.hyperlink_rules, {
    regex  = [[[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+]],
    format = "https://github.com/$0",
  })

  -- ── Bell ──────────────────────────────────────────────────────────────────
  config.audible_bell = "Disabled"
end

return M
