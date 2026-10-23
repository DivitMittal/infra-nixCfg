{
  pkgs,
  lib,
  inputs,
  hostPlatform,
  ...
}: let
  raycastExtensions = import ./_extensions.nix;
  mkRayCastExtension = inputs.vicinae.lib.${hostPlatform.system}.mkRayCastExtension;

  # Always fetch the source ourselves (rather than letting mkRayCastExtension's
  # default fetchFromGitHub run) since `name` (the extension's package.json
  # name, which vicinae loads it under) doesn't always match its
  # raycast/extensions checkout folder — see _extensions.nix.
  mkExtension = {
    name,
    folder ? name,
    hash,
  }:
    mkRayCastExtension {
      inherit name;
      src =
        pkgs.fetchFromGitHub {
          owner = "raycast";
          repo = "extensions";
          inherit (raycastExtensions) rev;
          sparseCheckout = ["/extensions/${folder}"];
          inherit hash;
        }
        + "/extensions/${folder}";
      # `ray build` otherwise pings its update-check/telemetry endpoints,
      # which just hang (retrying) since the build sandbox has no network.
      env = {
        CI = "true";
        NO_UPDATE_NOTIFIER = "1";
        RAYCAST_DISABLE_TELEMETRY = "1";
        DO_NOT_TRACK = "1";
      };
    };
in {
  imports = [inputs.vicinae.homeManagerModules.default];

  programs.vicinae =
    {
      enable = true;
      package = pkgs.vicinae;
      extensions = map mkExtension raycastExtensions.extensions;
      # Ported from a Raycast export: compact window mode was the one
      # preference with a direct, unambiguous vicinae equivalent. Global
      # hotkey, quicklinks (-> vicinae "Shortcuts") and snippets have no
      # declarative/CLI import path in vicinae today and are GUI/sqlite-only,
      # so those still need a one-time manual setup pass; the Google
      # Calendar, Notion and Spotify Player extensions also need re-auth
      # since Raycast's OAuth tokens don't transfer.
      settings = {
        launcher_window.compact_mode.enabled = true;
      };
    }
    // lib.optionalAttrs hostPlatform.isLinux {
      systemd.enable = true;
    }
    // lib.optionalAttrs hostPlatform.isDarwin {
      launchd.enable = true;
    };
}
