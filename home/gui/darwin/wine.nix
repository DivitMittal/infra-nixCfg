{
  hostPlatform,
  lib,
  ...
}: {
  homebrew.formulae = lib.optionals hostPlatform.isDarwin ["wine@staging"];
}
