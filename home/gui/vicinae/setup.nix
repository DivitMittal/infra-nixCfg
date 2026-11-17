{
  pkgs,
  lib,
  inputs,
  hostPlatform,
  ...
}: let
  raycastExtensions = import ./_extensions.nix;
  # Not inputs.vicinae.lib.<system>: that's built on vicinae's pinned nixpkgs,
  # which throws on x86_64-darwin. Same derivation, our pkgs.
  mkRayCastExtension = pkgs.callPackage "${inputs.vicinae}/nix/mkRayCastExtension.nix" {};

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
      # Written to nix.json and layered over the GUI's settings.json, so these
      # win over anything changed in the settings window. Still GUI/sqlite-only
      # (no declarative path in vicinae): quicklinks ("Shortcuts"), snippets,
      # and OAuth for the Google Calendar, Notion and Spotify Player extensions.
      settings = {
        # Hyper+Space, the key Raycast used (see the skhd notes on L1).
        # `control` is ⌘ and `super` is ⌃ on macOS, so this is all four
        # modifiers on both platforms, matching kanata's hyper.
        global_shortcuts.toggle = "control+super+alt+shift+space";

        # Raycast-like window behaviour: hide when focus leaves, and start
        # from root search on the next open.
        close_on_focus_loss = true;
        pop_to_root_on_close = true;
        launcher_window.compact_mode.enabled = true;

        # ctrl+j/k etc. in lists, in line with the rest of the setup.
        keybinding = "vim";

        # Updates come through the flake lock, not vicinae's own updater.
        updates.show_notice = false;
        telemetry.system_info = false;

        favorites = ["clipboard:history"];
        fallbacks = ["files:search"];

        # Raycast script commands (same `@raycast.*` header format); they use
        # `open`/AppleScript, so macOS only.
        providers.scripts.preferences.customDirs = lib.optionals hostPlatform.isDarwin ["${./scripts}"];
      };
    }
    // lib.optionalAttrs hostPlatform.isLinux {
      systemd.enable = true;
    }
    // lib.optionalAttrs hostPlatform.isDarwin {
      launchd.enable = true;
    };
}
