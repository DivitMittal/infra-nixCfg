{
  hostPlatform,
  lib,
  ...
}: {
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["wacom-tablet"];
}
