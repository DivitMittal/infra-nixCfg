{
  pkgs,
  hostPlatform,
  lib,
  ...
}: let
  ## Gcenx's unsigned build; Homebrew disabled every wine cask on 2026-09-01
  ## (fails_gatekeeper_check), but brew-nix still fetches it and a nix store
  ## copy carries no quarantine xattr, so Gatekeeper doesn't block it
  wineApp = pkgs.brewCasks."wine@staging";
  wineBin = "${wineApp}/Applications/Wine Staging.app/Contents/Resources/wine/bin";

  ## brew-nix only exposes a `wine@staging` launcher; put the CLI tools
  ## (wine, winecfg, wineserver, ...) on PATH as exec wrappers
  wine-staging = pkgs.symlinkJoin {
    name = "wine-staging-${wineApp.version}";
    paths = [wineApp];
    postBuild = ''
      for tool in "${wineBin}"/*; do
        printf '#!/bin/sh\nexec "%s" "$@"\n' "$tool" > "$out/bin/$(basename "$tool")"
        chmod +x "$out/bin/$(basename "$tool")"
      done
    '';
  };
in {
  home.packages = lib.optionals hostPlatform.isDarwin [wine-staging];
}
