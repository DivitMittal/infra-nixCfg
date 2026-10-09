{
  hostPlatform,
  lib,
  ...
}: {
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["wine@staging"];
}
