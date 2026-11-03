## Disabled: migrated to Vicinae. Kept for reference; the body is commented out
## (not deleted) because import-tree still imports this file, so it must stay a
## valid module.
_: {
  # raycast =
  #   if hostPlatform.isx86_64
  #   then (pkgs.brewCasks.raycast.override {variation = "tahoe";})
  #   else pkgs.brewCasks.raycast;
  #
  # home.packages = [raycast];
  #
  # xdg.configFile."raycast/scripts" = {
  #   enable = true;
  #   source = ../../vicinae/scripts; # moved: now loaded by vicinae
  #   recursive = true;
  # };
}
