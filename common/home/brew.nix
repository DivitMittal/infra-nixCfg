{
  inputs,
  hostPlatform,
  lib,
  pkgs,
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

  home.packages = lib.optionals hostPlatform.isDarwin [
    pkgs.customDarwin.zerobrew-bin
    (pkgs.writeShellScriptBin "brew-ultimate" ''
      echo "Running brew update..."
      brew update

      echo "Running brew upgrade..."
      brew upgrade

      echo "Running brew autoremove..."
      brew autoremove

      echo "Running brew cleanup..."
      brew cleanup -s --prune=0

      echo "Removing brew cache..."
      rm -rf "$(brew --cache)"

      echo "Brew maintenance complete!"
    '')
  ];
}
