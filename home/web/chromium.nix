{
  pkgs,
  hostPlatform,
  lib,
  ...
}: let
  # Google Chrome has no aarch64-linux build; fall back to open-source Chromium.
  useChrome = lib.meta.availableOn hostPlatform pkgs.google-chrome;
in {
  programs.chromium = {
    enable = true;
    package =
      if useChrome
      then pkgs.google-chrome
      else pkgs.chromium;

    commandLineArgs = lib.optionals (!hostPlatform.isDarwin) [
      "--ignore-gpu-blocklist"
      "--enable-gpu-rasterization"
      "--enable-parallel-downloading"
      "--enable-quic"
    ];

    # Only for open-source Chromium on Linux: home-manager asserts against
    # `extensions` for google-chrome on Linux (Chrome only loads external
    # extensions from system-managed dirs), and they never applied on darwin.
    # With Chrome, install these two from the Web Store instead.
    extensions = lib.optionals (!useChrome && hostPlatform.isLinux) [
      {id = "ddkjiahejlhfcafbddmgiahcphecmpfh";} # ublock-origin-lite
      {id = "hfjbmagddngcpeloejdejnfgbamkjaeg";} # vimiumC
    ];
  };
}
