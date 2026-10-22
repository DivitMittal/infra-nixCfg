{
  config,
  lib,
  hostPlatform,
  ...
}: {
  programs.home-manager.enable = true; # home-manager standalone

  home.stateVersion = lib.mkDefault "26.05";

  home = {
    username = lib.mkDefault config.hostSpec.username;
    homeDirectory = lib.mkDefault config.hostSpec.home;
    preferXdgDirectories = true;
    # x86_64-darwin is deliberately on Nixpkgs 26.05 under home-manager master
    enableNixpkgsReleaseCheck = !(hostPlatform.isDarwin && hostPlatform.isx86_64);
    language.base = "en_US.UTF-8";
  };

  ## home-manager manual
  manual = {
    html.enable = true;
    manpages.enable = true;
    json.enable = false;
  };

  xdg.enable = true;
  news.display = "show";
}
