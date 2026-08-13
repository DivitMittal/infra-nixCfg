{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["wacom-tablet"];

  home.packages = lib.optionals hostPlatform.isDarwin [pkgs.customDarwin.wacom-toggle];
}
