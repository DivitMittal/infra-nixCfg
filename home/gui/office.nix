{
  pkgs,
  hostPlatform,
  lib,
  ...
}: let
  sofficeWrapper = lib.optional hostPlatform.isDarwin (
    pkgs.writeShellScriptBin "soffice" ''
      exec ${pkgs.libreoffice-bin}/Applications/LibreOffice.app/Contents/MacOS/soffice "$@"
    ''
  );
in {
  # darwin-only apps below are `null` elsewhere; home.packages rejects nulls.
  home.packages =
    lib.filter (p: p != null) (lib.attrsets.attrValues {
      ## Office files (e.g., .docx, .xlsx, .pptx) editors/viewer
      onlyoffice =
        if hostPlatform.isDarwin
        then (pkgs.brewCasks.onlyoffice.override {variation = "tahoe";})
        else pkgs.onlyoffice-desktopeditors; # nixpkgs renamed it from onlyoffice
      libreoffice =
        if hostPlatform.isDarwin
        then
          pkgs.libreoffice-bin.overrideAttrs (oldAttrs: {
            installPhase =
              oldAttrs.installPhase
              + ''
                rm -f $out/bin/soffice
              '';
          })
        else pkgs.libreoffice;

      gimp =
        if hostPlatform.isDarwin
        then pkgs.brewCasks.gimp.override {variation = "tahoe";}
        else pkgs.gimp;

      microsoft-excel =
        if hostPlatform.isDarwin
        then
          pkgs.brewCasks.microsoft-excel.overrideAttrs (oldAttrs: {
            installPhase =
              oldAttrs.installPhase
              + ''
                # Clean Resources
                echo "Removing entire Resources directory from microsoft-excel installation..."
                local resource_dir="$out/Resources"

                if [ -d "$resource_dir" ]; then
                  echo "Found directory '$resource_dir' and removing it..."
                  rm -rf "$resource_dir"
                else
                  echo "Warning: Resources directory '$resource_dir' not found. It may have been removed already or path is wrong." >&2
                fi
                echo "Finished cleanup (removed Resources) for microsoft-excel."

                # Remove shared components to avoid collision with other Office apps
                echo "Removing shared licensing helper from microsoft-excel..."
                local helper_dir="$out/Library/PrivilegedHelperTools"
                if [ -d "$helper_dir" ]; then
                  rm -rf "$helper_dir"
                  echo "Removed PrivilegedHelperTools directory."
                fi

                echo "Removing Microsoft AutoUpdate app from microsoft-excel..."
                local autoupdate_app="$out/Applications/Microsoft AutoUpdate.app"
                if [ -d "$autoupdate_app" ]; then
                  rm -rf "$autoupdate_app"
                  echo "Removed Microsoft AutoUpdate.app"
                fi
              '';
          })
        else null;

      # microsoft-word =
      #   if hostPlatform.isDarwin
      #   then
      #     pkgs.brewCasks.microsoft-word.overrideAttrs (oldAttrs: {
      #       installPhase =
      #         oldAttrs.installPhase
      #         + ''
      #           # Clean Resources
      #           echo "Removing entire Resources directory from microsoft-word installation..."
      #           local resource_dir="$out/Resources"
      #
      #           if [ -d "$resource_dir" ]; then
      #             echo "Found directory '$resource_dir' and removing it..."
      #             rm -rf "$resource_dir"
      #           else
      #             echo "Warning: Resources directory '$resource_dir' not found. It may have been removed already or path is wrong." >&2
      #           fi
      #           echo "Finished cleanup (removed Resources) for microsoft-word."
      #
      #           # Remove shared components to avoid collision with other Office apps
      #           echo "Removing shared licensing helper from microsoft-word..."
      #           local helper_dir="$out/Library/PrivilegedHelperTools"
      #           if [ -d "$helper_dir" ]; then
      #             rm -rf "$helper_dir"
      #             echo "Removed PrivilegedHelperTools directory."
      #           fi
      #
      #           echo "Removing Microsoft AutoUpdate app from microsoft-word..."
      #           local autoupdate_app="$out/Applications/Microsoft AutoUpdate.app"
      #           if [ -d "$autoupdate_app" ]; then
      #             rm -rf "$autoupdate_app"
      #             echo "Removed Microsoft AutoUpdate.app"
      #           fi
      #         '';
      #     })
      #   else null;

      # microsoft-powerpoint =
      #   if hostPlatform.isDarwin
      #   then
      #     pkgs.brewCasks.microsoft-powerpoint.overrideAttrs (oldAttrs: {
      #       installPhase =
      #         oldAttrs.installPhase
      #         + ''
      #           # Clean Resources
      #           echo "Removing entire Resources directory from microsoft-powerpoint installation..."
      #           local resource_dir="$out/Resources"
      #
      #           if [ -d "$resource_dir" ]; then
      #             echo "Found directory '$resource_dir' and removing it..."
      #             rm -rf "$resource_dir"
      #           else
      #             echo "Warning: Resources directory '$resource_dir' not found. It may have been removed already or path is wrong." >&2
      #           fi
      #           echo "Finished cleanup (removed Resources) for microsoft-powerpoint."
      #
      #           # Remove shared components to avoid collision with other Office apps
      #           echo "Removing shared licensing helper from microsoft-powerpoint..."
      #           local helper_dir="$out/Library/PrivilegedHelperTools"
      #           if [ -d "$helper_dir" ]; then
      #             rm -rf "$helper_dir"
      #             echo "Removed PrivilegedHelperTools directory."
      #           fi
      #
      #           echo "Removing Microsoft AutoUpdate app from microsoft-powerpoint..."
      #           local autoupdate_app="$out/Applications/Microsoft AutoUpdate.app"
      #           if [ -d "$autoupdate_app" ]; then
      #             rm -rf "$autoupdate_app"
      #             echo "Removed Microsoft AutoUpdate.app"
      #           fi
      #         '';
      #     })
      #   else null;
    })
    ++ sofficeWrapper;
}
