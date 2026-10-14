{
  pkgs,
  hostPlatform,
  lib,
  ...
}: let
  onenote = pkgs.brewCasks.microsoft-onenote.overrideAttrs (oldAttrs: {
    installPhase =
      oldAttrs.installPhase
      + ''
        # Clean Resources
        echo "Removing entire Resources directory from microsoft-onenote installation..."
        local resource_dir="$out/Resources"

        if [ -d "$resource_dir" ]; then
          echo "Found directory '$resource_dir' and removing it..."
          rm -rf "$resource_dir"
        else
          echo "Warning: Resources directory '$resource_dir' not found. It may have been removed already or path is wrong." >&2
        fi
        echo "Finished cleanup (removed Resources) for microsoft-onenote."
      '';
  });
in {
  home.packages = lib.attrsets.attrValues {
    onenote =
      if hostPlatform.isDarwin
      then onenote
      else null;
    notion =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.notion.override {variation = "tahoe";}
      else null;
    # Official Excalidraw CLI (render .excalidraw → PNG, Excalidraw+ workspace)
    excalidraw-cli = lib.custom.mkPnpmDlxBin "excalidraw" "@excalidraw/cli@latest";
  };

  programs.obsidian = {
    enable = true;
    package =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.obsidian
      else pkgs.obsidian;
  };
}
