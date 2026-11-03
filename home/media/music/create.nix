{
  pkgs,
  lib,
  inputs,
  hostPlatform,
  ...
}: {
  imports = [
    inputs.tidalcycles-nix.homeManagerModules.default
  ];

  home.packages = lib.attrsets.attrValues {
    librescore = lib.custom.mkPnpmDlxBin "dl-librescore" "dl-librescore@latest";
  };

  programs.tidalcycles = {
    enable = true;

    # Use standard profile (recommended)
    boot.profile = "standard";

    # SuperCollider configuration
    supercollider = {
      enable = true;
      # brewCasks only exists on darwin (brew-nix overlay).
      package =
        if hostPlatform.isDarwin
        then pkgs.brewCasks.supercollider
        else pkgs.supercollider;
    };

    # SuperDirt configuration
    superdirt.enable = true;
  };
}
