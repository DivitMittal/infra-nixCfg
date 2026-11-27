-- Device-local UI choices override these defaults. Configure provider/model/key there.
return {
    features = {
        -- Completed responses avoid repeated e-ink refreshes while tokens arrive.
        enable_streaming = false,
        stream_auto_scroll = false,
        render_markdown = true,
        markdown_font_size = 22,
        auto_check_updates = false,
        enable_web_search = false,
        -- These actions use the selected passage, not a scan of the whole library.
        enable_book_text_extraction = "never",
        enable_library_scanning = "never",
        enable_advanced_stats = "never",
        trusted_providers = {},
    },
}
