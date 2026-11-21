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

  # Older API tarballs contain only a downloader in bin/ray, which curls the
  # CLI at build time and fails in the sandbox. Pin the matching CLI per
  # platform (cli.raycast.com/<version>/<dir>/ray) as a fixed-output fetch.
  legacyCliDir =
    if hostPlatform.isLinux && hostPlatform.isx86_64
    then "linux"
    else if hostPlatform.isDarwin && hostPlatform.isx86_64
    then "x86"
    else if hostPlatform.isDarwin && hostPlatform.isAarch64
    then "arm64"
    else null;
  legacyCliHashes = {
    linux = {
      "1.39.0" = "sha256-7TUjuicfSRvPpcHwgyCQ2lO2eRX7VSpxF+oS8ZEPF3I=";
      "1.46.0" = "sha256-gBhzA5gN7gRbOzWYGZM1eU829W7oQUk6PIHKFB3g7ho=";
      "1.47.3" = "sha256-oJwgzYXpfr6Zr1fYdbbO4aVimUR+sqpIJG/ZMpZNPGg=";
      "1.80.0" = "sha256-lVkAElCQH1RSsZN+yLPyEjjOGILhrem+IL1KW6kyC7s=";
    };
    x86 = {
      "1.39.0" = "sha256-eybncsn/jIhQYDHFz4SKT7SNG6eZVSq16oSriaX2BHY=";
      "1.46.0" = "sha256-hv9hiSks8lPp2JaF78khusvTDVZl+hL4aeV9qLFA7eQ=";
      "1.47.3" = "sha256-ItUS75BhpdV9RwF7vyVa9dz1AmFSBHg2uRz4+r0+Wss=";
      "1.80.0" = "sha256-zQsTHLjJlBm7R8Y19ktTaW01DEWnAghCPVM4uzVnKgc=";
    };
    arm64 = {
      "1.39.0" = "sha256-Ow9zH5QlXK2W2NOsv00GqJs6Y+X9YeYMhCTXPVwjODw=";
      "1.46.0" = "sha256-5fZxhtuQAq02awkfh8EpZhL7F7IW5rc60YysgtKYoy8=";
      "1.47.3" = "sha256-QVM3F2aYNcCYN4Y5f3NKyIJK3d619nCz8cidkLR5DZI=";
      "1.80.0" = "sha256-lkjHnpluadt5r/h+Xr5NWJlABdqpCeP7jXY1WQy0PMw=";
    };
  };
  platformCliHashes =
    if legacyCliDir == null
    then {}
    else legacyCliHashes.${legacyCliDir};

  # Always fetch the source ourselves (rather than letting mkRayCastExtension's
  # default fetchFromGitHub run) since `name` (the extension's package.json
  # name, which vicinae loads it under) doesn't always match its
  # raycast/extensions checkout folder — see _extensions.nix.
  mkExtension = {
    name,
    folder ? name,
    hash,
  }: let
    src =
      pkgs.fetchFromGitHub {
        owner = "raycast";
        repo = "extensions";
        inherit (raycastExtensions) rev;
        sparseCheckout = ["/extensions/${folder}"];
        inherit hash;
      }
      + "/extensions/${folder}";
    lock = builtins.fromJSON (builtins.readFile (src + "/package-lock.json"));
    apiVersion = lock.packages."node_modules/@raycast/api".version;
    legacyCli = pkgs.fetchurl {
      url = "https://cli.raycast.com/${apiVersion}/${legacyCliDir}/ray";
      hash = platformCliHashes.${apiVersion};
    };
  in
    mkRayCastExtension ({
        inherit name src;
        # `ray build` otherwise pings its update-check/telemetry endpoints,
        # which just hang (retrying) since the build sandbox has no network.
        env =
          {
            CI = "true";
            NO_UPDATE_NOTIFIER = "1";
            RAYCAST_DISABLE_TELEMETRY = "1";
            DO_NOT_TRACK = "1";
          }
          // lib.optionalAttrs (name == "stock-tracker") {
            # react-devtools brings Electron for its standalone developer UI;
            # stock commands and `ray build` only need Node and esbuild.
            ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
          };
      }
      // lib.optionalAttrs (builtins.hasAttr apiVersion platformCliHashes) {
        # The upstream CLIs are Go executables (static on Linux, system
        # frameworks only on macOS). Replace the downloader directly: API
        # 1.39.0's wrapper also runs `file /usr/local`.
        preBuild = ''
          install -m755 ${legacyCli} node_modules/@raycast/api/bin/ray
          test "$(node_modules/.bin/ray version)" = ${lib.escapeShellArg apiVersion}
        '';
      });
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
