{
  inputs,
  hostPlatform,
  lib,
  ...
}: {
  imports = [inputs.home-manager-brew.homeManagerModules.default];

  homebrew = {
    enable = hostPlatform.isDarwin;
    cleanup = true; # plain `brew bundle cleanup --force`, no zap
    update = false; # matches nix-darwin's old global.autoUpdate=false / onActivation.autoUpdate=false
    upgrade = true; # matches nix-darwin's old onActivation.upgrade=true
  };

  home.sessionVariables = lib.mkIf hostPlatform.isDarwin {
    HOMEBREW_NO_ENV_HINTS = "1";
  };
}
