{
  pkgs,
  lib,
  hostPlatform,
  ...
}: let
  # Both vendors delete superseded releases from their primary CDN, so the
  # brew-api pin 404s soon after an update. Try a mirror that keeps old
  # releases first; the cask's fixed sha256 still guards the download.
  withArchiveMirror = cask: mirror:
    cask.overrideAttrs (old: {
      src = old.src.overrideAttrs (src: {
        urls = [(mirror cask.version)] ++ src.urls;
      });
    });
in {
  home.packages =
    lib.optionals hostPlatform.isDarwin [
      (withArchiveMirror pkgs.brewCasks.mullvad-browser
        (v: "https://github.com/mullvad/mullvad-browser/releases/download/${v}/mullvad-browser-macos-${v}.dmg"))
      (withArchiveMirror pkgs.brewCasks.tor-browser
        (v: "https://archive.torproject.org/tor-package-archive/torbrowser/${v}/tor-browser-macos-${v}.dmg"))
    ]
    ++ lib.optionals (hostPlatform.system == "x86_64-linux") [
      pkgs.mullvad-browser
      pkgs.tor-browser
    ]
    ++ lib.optionals (hostPlatform.system == "i686-linux") [
      pkgs.tor-browser
    ];
}
