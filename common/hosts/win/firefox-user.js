// Managed by nix-win — do not edit by hand.
// Firefox user.js — privacy and behaviour hardening. Based on arkenfox/user.js principles.

// ── Startup ──────────────────────────────────────────────────────────────────
user_pref("browser.startup.page", 3); // Restore previous session
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.newtabpage.enabled", false); // Blank new tab
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref(
  "browser.newtabpage.activity-stream.section.highlights.includePocket",
  false,
);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.default.sites", "");

// ── Geolocation ───────────────────────────────────────────────────────────────
user_pref("geo.provider.network.url", "");
user_pref("geo.enabled", false);

// ── Telemetry ─────────────────────────────────────────────────────────────────
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.sessions.current.clean", true);
user_pref("devtools.onboarding.telemetry.logged", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.coverage.opt-out", true);
user_pref("toolkit.coverage.opt-out", true);
user_pref("toolkit.coverage.endpoint.base", "");
user_pref("browser.ping-centre.telemetry", false);
user_pref("beacon.enabled", false);

// ── Safe Browsing (sends URLs to Google) ─────────────────────────────────────
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.enabled", false);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);

// ── DNS-over-HTTPS ────────────────────────────────────────────────────────────
// 2 = on, 3 = on with fallback, 5 = off
user_pref("network.trr.mode", 2);
user_pref("network.trr.uri", "https://dns.quad9.net/dns-query");

// ── Tracking protection ───────────────────────────────────────────────────────
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.donottrackheader.enabled", true);
user_pref("privacy.globalprivacycontrol.enabled", true);

// ── Fingerprinting ────────────────────────────────────────────────────────────
user_pref("privacy.resistFingerprinting", false); // Breaks too much; use uBO instead
user_pref("privacy.fingerprintingProtection", true);
user_pref("webgl.disabled", false);

// ── Containers ────────────────────────────────────────────────────────────────
user_pref("privacy.userContext.enabled", true);
user_pref("privacy.userContext.ui.enabled", true);

// ── UI / UX ───────────────────────────────────────────────────────────────────
user_pref("browser.compactmode.show", true);
user_pref("browser.uidensity", 1); // 0=normal, 1=compact
user_pref("browser.tabs.tabMinWidth", 76);
user_pref("browser.tabs.closeTabByDblclick", true);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.urlbar.dnsResolveSingleWordsAfterSearch", 0);
user_pref("full-screen-api.transition-duration.enter", "0 0");
user_pref("full-screen-api.transition-duration.leave", "0 0");
user_pref("full-screen-api.warning.timeout", 0);

// ── Downloads ─────────────────────────────────────────────────────────────────
user_pref("browser.download.useDownloadDir", false); // Always ask where to save

// ── Misc hardening ────────────────────────────────────────────────────────────
user_pref("dom.disable_open_during_load", true);
user_pref("dom.popup_maximum", 3);
user_pref("network.http.sendRefererHeader", 2);
user_pref("network.http.referer.XOriginPolicy", 2);
user_pref("security.mixed_content.block_active_content", true);
user_pref("security.mixed_content.block_display_content", true);
