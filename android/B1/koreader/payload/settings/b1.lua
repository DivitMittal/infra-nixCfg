-- Managed global defaults; existing per-book settings continue to take priority.
return {
    globals = {
        copt_font_size = 24,
        copt_line_spacing = 110,
        copt_h_page_margins = { 10, 10 },
        copt_t_page_margin = 12,
        copt_b_page_margin = 12,
        -- Retain PDF equations/figures by default; reflow is a separate profile.
        kopt_text_wrap = 0,
        kopt_trim_page = 1,
        kopt_page_scroll = 0,
        default_highlight_action = "ask",
    },
    plugins = {
        "koassistant", "exporter", "profiles", "gestures", "opds",
        "newsdownloader", "vocabbuilder", "statistics",
    },
    profiles = {
        ["B1 EPUB"] = {
            settings = {
                name = "B1 EPUB", registered = true,
                order = { "font_size", "line_spacing", "h_page_margins" },
            },
            font_size = 24, line_spacing = 110, h_page_margins = { 10, 10 },
        },
        ["B1 Paper original"] = {
            settings = {
                name = "B1 Paper original", registered = true,
                order = { "kopt_text_wrap", "kopt_trim_page", "kopt_page_scroll" },
            },
            kopt_text_wrap = 0, kopt_trim_page = "auto", kopt_page_scroll = false,
        },
        ["B1 Paper reflow"] = {
            settings = {
                name = "B1 Paper reflow", registered = true,
                order = { "kopt_text_wrap", "kopt_page_scroll" },
            },
            kopt_text_wrap = 1, kopt_page_scroll = false,
        },
    },
}
