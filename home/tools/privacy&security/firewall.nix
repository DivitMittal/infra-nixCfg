{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  ## Objective-See firewall + persistence/malware scanner.
  ## LuLu stays a Homebrew cask: its network filter is a system extension,
  ## which macOS only activates from an app in /Applications
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["lulu"];
  home.packages = lib.optionals hostPlatform.isDarwin [pkgs.brewCasks.knockknock];
}
