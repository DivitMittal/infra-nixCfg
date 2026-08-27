{
  pkgs,
  lib,
  inputs,
  hostPlatform,
  ...
}: {
  imports = [inputs.vicinae.homeManagerModules.default];

  programs.vicinae =
    {
      enable = true;
      package = pkgs.vicinae;
    }
    // lib.optionalAttrs hostPlatform.isLinux {
      systemd.enable = true;
    }
    // lib.optionalAttrs hostPlatform.isDarwin {
      launchd.enable = true;
    };
}
