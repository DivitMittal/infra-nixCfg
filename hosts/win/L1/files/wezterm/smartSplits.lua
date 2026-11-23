-- Smart Splits integration for WezTerm
-- Allows seamless navigation between WezTerm panes and Neovim splits
-- using the same keybindings (Ctrl+h/j/k/l).
local wezterm = require("wezterm")

local function is_vim(pane)
  local process = pane:get_foreground_process_name()
  return process and (
    process:find("nvim") or
    process:find("vim")  or
    process:find("vi")
  )
end

local directions = {
  h = "Left", j = "Down", k = "Up", l = "Right"
}

for key, direction in pairs(directions) do
  wezterm.on("ActivatePaneDirection-" .. key, function(window, pane)
    if is_vim(pane) then
      -- Pass through to Neovim
      window:perform_action(
        wezterm.action.SendKey { key = key, mods = "CTRL" },
        pane
      )
    else
      window:perform_action(
        wezterm.action.ActivatePaneDirection(direction),
        pane
      )
    end
  end)
end
