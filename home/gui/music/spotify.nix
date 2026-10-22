{
  config,
  inputs,
  hostPlatform,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption;
  spicePkgs = inputs.spicetify-nix.legacyPackages.${hostPlatform.system};
  cfg = config.programs.spotify;

  stockSpotify =
    if hostPlatform.isDarwin
    then
      (pkgs.brewCasks.spotify.override {
        variation = "tahoe";
      }).overrideAttrs (oldAttrs: {
        src = pkgs.fetchurl {
          url = lib.lists.head oldAttrs.src.urls;
          hash = "sha256-4Lm4g0gAQ3EA7Sj2wDTbjEXRxcNoGWHLvdEx/57nry4=";
        };
      })
    else pkgs.spotify;
in {
  imports = [inputs.spicetify-nix.homeManagerModules.default];

  options.programs.spotify = {
    # Spicetify patches Spotify, so the two are mutually exclusive — pick one.
    mode = mkOption {
      type = lib.types.enum ["spicetify" "stock"];
      # spicetify-nix builds the spiced client from its own nixpkgs input,
      # which throws on x86_64-darwin (Nixpkgs 26.11+).
      default =
        if hostPlatform.system == "x86_64-darwin"
        then "stock"
        else "spicetify";
      description = ''
        Which Spotify installation to use. `spicetify` enables the customized
        Spicetify client (with the extensions, snippets, and apps configured
        below); `stock` installs vanilla Spotify and leaves Spicetify disabled.
      '';
    };
  };

  config = {
    programs.spicetify = mkIf (cfg.mode == "spicetify") {
      enable = true;

      theme = lib.mkForce (spicePkgs.themes.text
        // {
          # Disable every transition in the text theme — they're the main perf cost.
          additionalCss = ":root { --border-transition: none !important; }";
        });
      colorScheme = lib.mkForce "Spotify";

      enabledExtensions = with spicePkgs.extensions; [
        keyboardShortcut
        adblockify
        songStats
      ];

      enabledSnippets = with spicePkgs.snippets; [
        beSquare
      ];

      enabledCustomApps = with spicePkgs.apps; [
        lyricsPlus
        historyInSidebar
      ];

      experimentalFeatures = true;
    };

    home.packages = mkIf (cfg.mode == "stock") [stockSpotify];
  };
}
