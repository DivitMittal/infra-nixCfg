{
  pkgs,
  lib,
  hostPlatform,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    outlook =
      if hostPlatform.isDarwin
      then
        (pkgs.brewCasks.microsoft-outlook.overrideAttrs (oldAttrs: {
          installPhase =
            oldAttrs.installPhase
            + ''
              # Clean Resources
              echo "Removing entire Resources directory from microsoft-outlook installation..."
              local resource_dir="$out/Resources"

              if [ -d "$resource_dir" ]; then
                echo "Found directory '$resource_dir' and removing it..."
                rm -rf "$resource_dir"
              else
                echo "Warning: Resources directory '$resource_dir' not found. It may have been removed already or path is wrong." >&2
              fi
              echo "Finished cleanup (removed Resources) for microsoft-outlook."

              # Remove shared components to avoid collision with other Office apps
              echo "Removing shared licensing helper from microsoft-outlook..."
              local helper_dir="$out/Library/PrivilegedHelperTools"
              if [ -d "$helper_dir" ]; then
                rm -rf "$helper_dir"
                echo "Removed PrivilegedHelperTools directory."
              fi

              echo "Removing Microsoft AutoUpdate app from microsoft-outlook..."
              local autoupdate_app="$out/Applications/Microsoft AutoUpdate.app"
              if [ -d "$autoupdate_app" ]; then
                rm -rf "$autoupdate_app"
                echo "Removed Microsoft AutoUpdate.app"
              fi
            '';
        }))
      else null;

    whatsapp =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.whatsapp
      else null;

    inherit (pkgs) vesktop;

    telegram =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.telegram
      else pkgs.telegram-desktop;

    matrix =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.element
      else pkgs.element-desktop;

    rustdesk =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.rustdesk
      else pkgs.rustdesk;
  };
}
