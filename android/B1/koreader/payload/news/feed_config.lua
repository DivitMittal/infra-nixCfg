-- Manual downloads only. Add selected RSSHub route URLs here, not its base URL.
-- Keep the starting feed small on a 16 GB reader; Feeder remains the daily inbox.
return {
    {
        "https://github.com/koreader/koreader/releases.atom",
        limit = 3,
        download_full_article = false,
        include_images = false,
    },
    -- { "http://T3.lan:31200/ROUTE", limit = 10, download_full_article = false, include_images = false },
}
