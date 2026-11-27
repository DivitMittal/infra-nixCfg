{
  config,
  lib,
  ...
}: let
  catalog = import ./catalog.nix;
  candidates = builtins.attrNames catalog.candidates;
in {
  options.boox.disabledPackages = lib.mkOption {
    type = with lib.types; listOf (enum candidates);
    default = [];
    description = "Individually reviewed C69 debloat candidates to keep disabled for user 0";
  };

  # Narrow the upstream option too, so direct declarations cannot accidentally
  # disable the launcher, sleep-screen dependencies or an unreviewed package.
  options.android.packages.disabled = lib.mkOption {
    apply = packages:
      if lib.all (package: builtins.elem package candidates) packages
      then packages
      else throw "B1: disable only reviewed candidates from android/B1/catalog.nix; preserve Onyx sleep-screen dependencies";
  };

  config = {
    android.packages.disabled = lib.unique config.boox.disabledPackages;
  };
}
