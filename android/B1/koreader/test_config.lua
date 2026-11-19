-- Exercises the startup patch without a device, using KOReader's settings API shape.
local root = assert(arg[1], "pass the payload directory")
local function settings(data)
    return {
        data = data,
        readSetting = function(self, key, default)
            local value = self.data[key]
            if value == nil then return default end
            return value
        end,
        saveSetting = function(self, key, value) self.data[key] = value end,
        flush = function(self) self.flushed = true end,
    }
end

G_reader_settings = settings({
    language = "en_GB",
    plugins_disabled = { koassistant = true, newsdownloader = true, chess = true },
    exporter = { json = { enabled = true }, markdown = { custom = "retained" } },
    vocabulary_builder = { custom = "retained" },
})
local profiles = settings({ ["My profile"] = { font_size = 30 } })
package.preload.datastorage = function()
    return {
        getSettingsDir = function() return root .. "/settings" end,
        getFullDataDir = function() return "/sdcard/koreader" end,
    }
end
package.preload.luasettings = function()
    return { open = function(_, path)
        assert(path == root .. "/settings/profiles.lua")
        return profiles
    end }
end

for _ = 1, 2 do
    dofile(root .. "/patches/2-b1-reading.lua")
    local current = G_reader_settings.data
    assert(current.language == "en_GB")
    assert(current.copt_font_size == 24 and current.copt_line_spacing == 110)
    assert(current.kopt_text_wrap == 0 and current.kopt_page_scroll == 0)
    assert(current.plugins_disabled.chess and not current.plugins_disabled.koassistant)
    assert(not current.plugins_disabled.newsdownloader)
    assert(current.exporter.json.enabled and current.exporter.markdown.enabled)
    assert(current.exporter.markdown.custom == "retained")
    assert(current.exporter.clipping_dir == "/sdcard/koreader/exports")
    assert(current.vocabulary_builder.enabled and current.vocabulary_builder.custom == "retained")
    assert(profiles.data["My profile"].font_size == 30)
    assert(profiles.data["B1 Paper original"].kopt_trim_page == "auto")
    assert(profiles.data["B1 Paper reflow"].kopt_text_wrap == 1 and profiles.flushed)
end

local actions = dofile(root .. "/plugins/koassistant.koplugin/custom_actions.lua")
assert(#actions == 5)
local names = {}
for _, action in ipairs(actions) do
    assert(action.context == "highlight" and action.include_book_context)
    assert(action.prompt:find("{highlighted_text}", 1, true))
    assert(not names[action.text] and action.api_params.max_tokens <= 1200)
    names[action.text] = true
end
local configuration = dofile(root .. "/plugins/koassistant.koplugin/configuration.lua")
assert(not configuration.features.enable_streaming)
assert(not configuration.features.auto_check_updates)
assert(configuration.features.enable_book_text_extraction == "never")
assert(configuration.provider == nil and configuration.api_key == nil)
print("Lua configuration: merge preservation, repeat application, profiles and research actions pass")
