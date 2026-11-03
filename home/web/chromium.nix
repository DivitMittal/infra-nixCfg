{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  programs.chromium = {
    enable = true;
    package = pkgs.google-chrome;

    commandLineArgs = lib.optionals (!hostPlatform.isDarwin) [
      "--ignore-gpu-blocklist"
      "--enable-gpu-rasterization"
      "--enable-parallel-downloading"
      "--enable-quic"
    ];

    # No `extensions`: home-manager now asserts against them for google-chrome
    # on Linux (Chrome only loads external extensions from system-managed
    # dirs), and they never applied on darwin. Install uBlock Origin Lite
    # (ddkjiahejlhfcafbddmgiahcphecmpfh) and Vimium C
    # (hfjbmagddngcpeloejdejnfgbamkjaeg) from the Web Store instead.
  };
}
