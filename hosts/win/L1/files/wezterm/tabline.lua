-- WezTerm custom tab line
local M = {}

function M.apply(config, wezterm)
  wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
    local pane  = tab.active_pane
    local title = tab.tab_title ~= "" and tab.tab_title or pane.title
    local index = tab.tab_index + 1  -- 1-based display

    -- Truncate long titles
    if #title > max_width - 4 then
      title = wezterm.truncate_right(title, max_width - 5) .. "…"
    end

    local is_active = tab.is_active
    local fg = is_active and "#cdd6f4" or "#6c7086"
    local bg = is_active and "#313244" or "#1e1e2e"

    return {
      { Background = { Color = bg } },
      { Foreground = { Color = fg } },
      { Text = string.format(" %d: %s ", index, title) },
    }
  end)
end

return M
