{
  pkgs,
  hostPlatform,
  lib,
  ...
}: let
  ## REAPER plugin directory (platform-specific)
  pluginsDir =
    if hostPlatform.isDarwin
    then "Library/Application Support/REAPER/UserPlugins"
    else ".config/REAPER/UserPlugins";

  ## Arch suffix used in extension filenames; Darwin calls aarch64 "arm64"
  swsArch =
    if hostPlatform.isAarch64
    then
      (
        if hostPlatform.isDarwin
        then "arm64"
        else "aarch64"
      )
    else "x86_64";

  ext =
    if hostPlatform.isDarwin
    then "dylib"
    else "so";

  ## nixpkgs reaper-sws-extension and reaper-reapack-extension darwin.nix have an unpack
  ## bug (dontUnpack=true but installPhase uses `*` glob); use custom derivations instead
  swsPkg =
    if hostPlatform.isDarwin
    then pkgs.customDarwin.reaper-sws-extension
    else pkgs.reaper-sws-extension;

  reapackPkg =
    if hostPlatform.isDarwin
    then pkgs.customDarwin.reaper-reapack-extension
    else pkgs.reaper-reapack-extension;
in {
  home.packages = [
    pkgs.custom.reaper-bin
    swsPkg
    reapackPkg
  ];

  home.file = {
    ## Reaper SWS
    "${pluginsDir}/reaper_sws-${swsArch}.${ext}".source = "${swsPkg}/UserPlugins/reaper_sws-${swsArch}.${ext}";
    ## Reapack
    "${pluginsDir}/reaper_reapack-${swsArch}.${ext}".source = "${reapackPkg}/UserPlugins/reaper_reapack-${swsArch}.${ext}";
  };

  ## BlackHole virtual audio device, for routing system audio into REAPER for recording
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["blackhole-2ch"];
}
