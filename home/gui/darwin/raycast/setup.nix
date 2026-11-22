## Kept alongside Vicinae while trialling it; drop once the migration sticks.
{
  pkgs,
  hostPlatform,
  ...
}: let
  # Raycast 2.x is arm64-only; the cask's `sequoia` variation is the last
  # x86_64 build (1.x), so Intel Macs fall back to it.
  raycast =
    if hostPlatform.isx86_64
    then (pkgs.brewCasks.raycast.override {variation = "sequoia";})
    else pkgs.brewCasks.raycast;
in {
  home.packages = [raycast];

  # Same script commands Vicinae loads (identical `@raycast.*` format).
  xdg.configFile."raycast/scripts" = {
    enable = true;
    source = ../../vicinae/scripts;
    recursive = true;
  };
}
