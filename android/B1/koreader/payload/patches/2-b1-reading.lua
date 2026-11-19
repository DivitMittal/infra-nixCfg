-- Priority 2 runs after G_reader_settings exists, before reader plugins load.
-- Only managed keys and named profiles are changed; never replace settings.reader.lua.
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local spec = dofile(DataStorage:getSettingsDir() .. "/b1.lua")
assert(type(spec) == "table", "B1 reading configuration must return a table")

for key, value in pairs(spec.globals) do
    G_reader_settings:saveSetting(key, value)
end

local disabled = G_reader_settings:readSetting("plugins_disabled", {})
for _, name in ipairs(spec.plugins) do
    disabled[name] = nil
end
G_reader_settings:saveSetting("plugins_disabled", disabled)

local exporter = G_reader_settings:readSetting("exporter", {})
exporter.markdown = exporter.markdown or {}
exporter.markdown.enabled = true
exporter.markdown.export_backlinks = true
exporter.clipping_dir = DataStorage:getFullDataDir() .. "/exports"
G_reader_settings:saveSetting("exporter", exporter)

local vocabulary = G_reader_settings:readSetting("vocabulary_builder", {})
vocabulary.enabled = true
vocabulary.with_context = true
G_reader_settings:saveSetting("vocabulary_builder", vocabulary)

local profiles = LuaSettings:open(DataStorage:getSettingsDir() .. "/profiles.lua")
for name, profile in pairs(spec.profiles) do
    profiles:saveSetting(name, profile)
end
profiles:flush()
