{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  programs.mpv = {
    enable = true;
    package =
      if hostPlatform.isDarwin
      then
        ((pkgs.brewCasks.stolendata-mpv.override
          {
            variation = "tahoe";
          }).overrideAttrs (oldAttrs: {
          nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [pkgs.gnutar];
          unpackPhase = ''
            tar -xvzf $src
          '';
        }))
      else pkgs.mpv-unwrapped;

    bindings = {
      "n" = "seek -10";
      "i" = "seek +10";
    };

    config = {
      force-window = true;
    };
  };
  ## HyperHDR — ambient lighting (Ambilight) driven by screen/video capture
  home.packages = [
    (
      if hostPlatform.isDarwin
      then pkgs.customDarwin.hyperhdr-bin
      else pkgs.hyperhdr
    )
  ];

  home.shellAliases = lib.mkIf hostPlatform.isDarwin {
    mpv = "stolendata-mpv";
  };
}
