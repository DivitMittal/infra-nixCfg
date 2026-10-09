{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    # au-lab =
    #   if hostPlatform.isDarwin
    #   then
    #     (pkgs.brewCasks.au-lab.overrideAttrs (oldAttrs: {
    #       src = pkgs.fetchurl {
    #         url = lib.lists.head oldAttrs.src.urls;
    #         hash = "sha256-sjlpgwwtaF4ldr8EI3Cpzboai+7eYj8LvrBjWf7chFk=";
    #       };
    #     }))
    #   else null;

    ## Musescore Score Editor
    musescore =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.musescore
      else pkgs.musescore;
  };

  ## Vendor plugin/instrument managers; they install into system plugin dirs,
  ## so they go through brew rather than brew-nix
  homebrew.casks = lib.optionals hostPlatform.isDarwin [
    "native-access" # Native Instruments (Kontakt, Komplete)
    "inmusic-software-center" # inMusic (Akai Professional, AIR Music Technology)
    "mpluginmanager" # MeldaProduction
  ];

  homebrew.mas = lib.optionals hostPlatform.isDarwin [
    # {
    #   name = "Capo"; # song transcription / slow-down
    #   id = 696977615;
    # }
  ];
}
