-- WezTerm main configuration entry point
-- Loads modular config files from the same directory.
local wezterm = require("wezterm")
local options = require("options")
local binds   = require("binds")
local tabline = require("tabline")

local config = wezterm.config_builder()

-- Apply each module's configuration to the builder
options.apply(config)
binds.apply(config)
tabline.apply(config, wezterm)

return config
