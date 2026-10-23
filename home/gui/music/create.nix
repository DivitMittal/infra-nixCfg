{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  home.packages = lib.attrsets.attrValues ({
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
    }
    // lib.optionalAttrs hostPlatform.isDarwin {
      ## inMusic (Akai Professional, AIR Music Technology) installer/manager
      inherit (pkgs.brewCasks) inmusic-software-center;
    });

  ## Vendor plugin/instrument managers kept on Homebrew:
  ## - native-access: unversioned "latest" download (brew-nix can't pin its
  ##   hash) and a privileged helper
  ## - mpluginmanager: .pkg installer
  homebrew.casks = lib.optionals hostPlatform.isDarwin [
    "native-access" # Native Instruments (Kontakt, Komplete)
    "mpluginmanager" # MeldaProduction
  ];

  homebrew.mas = lib.optionals hostPlatform.isDarwin [
    # {
    #   name = "Capo"; # song transcription / slow-down
    #   id = 696977615;
    # }
  ];
}
