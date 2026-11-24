{
  lib,
  pkgs,
  self,
  ...
}: {
  # Keep the target out of home.packages. The source snapshot makes this work
  # before pushing changes, and does not retain the zlib application closure.
  # zbx currently cannot launch heartleo/tap/zlib-cli: it looks for bin/zlib-cli,
  # but upstream installs bin/zlib. Do not use the unrelated core zlib formula.
  home.packages = [
    (lib.custom.mkNixRunBin pkgs "zlib" "${self.outPath}#zlib-cli")
  ];
}
