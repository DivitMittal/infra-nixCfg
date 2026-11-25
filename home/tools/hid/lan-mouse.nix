{
  config,
  inputs,
  lib,
  hostPlatform,
  pkgs,
  ...
}: let
  desk = import ../../../lib/lan-mouse.nix {inherit lib;};
  hostName = config.hostSpec.hostName;
  # L2 here is the separate NixOS boot; its Windows boot uses the exported spec.
  deskHost = builtins.elem hostName ["L1" "T2"];
  waylandFeatures = ["--features" "layer_shell_capture,wlroots_emulation"];
  # Use the same upstream release as L2 Windows. A newer source build can
  # still report 0.11.0 but send protocol events that L2 cannot decode.
  upstreamApp =
    pkgs.runCommand "lan-mouse-0.11.0" {
      nativeBuildInputs = [pkgs.unzip];
      src = pkgs.fetchurl {
        url = "https://github.com/feschber/lan-mouse/releases/download/v0.11.0/lan-mouse-macos-intel.zip";
        hash = "sha256-0kw4zPUAYatxCCYAPBnRDhJDQV/6GPQh1EmLK4WMi2Q=";
      };
      meta.mainProgram = "lan-mouse";
    } ''
      mkdir -p "$out/Applications" "$out/bin"
      unzip -q "$src" 'Lan Mouse.app/*' -d "$out/Applications"
      ln -s "$out/Applications/Lan Mouse.app/Contents/MacOS/lan-mouse" "$out/bin/lan-mouse"
    '';
  package =
    if hostPlatform.system == "x86_64-darwin"
    then upstreamApp
    else
      inputs.lan-mouse.packages.${hostPlatform.system}.default.overrideAttrs (_: {
        buildInputs = [];
        # Disabling the GTK frontend must not also disable Linux input support.
        cargoBuildFlags = ["--no-default-features"] ++ lib.optionals hostPlatform.isLinux waylandFeatures;
        cargoTestFlags = ["--no-default-features"] ++ lib.optionals hostPlatform.isLinux waylandFeatures;
      });
  macApp = "${config.home.homeDirectory}/Applications/Lan Mouse Desktop.app";
  # The built package wraps its binary; the upstream release ships it unwrapped.
  macBinary = "${package}/bin/${
    if hostPlatform.system == "x86_64-darwin"
    then "lan-mouse"
    else ".lan-mouse-wrapped"
  }";
  macBundleId = "org.divitmittal.lan-mouse";
  macAppInfo = pkgs.writeText "lan-mouse-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>lan-mouse</string>
      <key>CFBundleIdentifier</key><string>${macBundleId}</string>
      <key>CFBundleName</key><string>Lan Mouse Desktop</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleVersion</key><string>1</string>
      <key>LSUIElement</key><true/>
      <key>NSLocalNetworkUsageDescription</key>
      <string>Share mouse and keyboard with L2 and T2 on the local network.</string>
    </dict></plist>
  '';
in {
  imports = [inputs.lan-mouse.homeManagerModules.default];

  programs.lan-mouse = {
    enable = true;
    inherit package;
    systemd = hostPlatform.isLinux;
    launchd = hostPlatform.isDarwin;
    settings = desk.settingsFor (
      if deskHost
      then hostName
      else ""
    );
  };

  systemd.user.services.lan-mouse = lib.mkIf hostPlatform.isLinux {
    Install.WantedBy = lib.mkForce (lib.optionals deskHost ["sway-session.target"]);
    Unit.PartOf = ["graphical-session.target"];
    Service = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  launchd.agents.lan-mouse.config = lib.mkIf hostPlatform.isDarwin {
    KeepAlive = lib.mkForce deskHost;
    RunAtLoad = deskHost;
    StandardOutPath = "${config.xdg.cacheHome}/lan-mouse.log";
    StandardErrorPath = "${config.xdg.cacheHome}/lan-mouse.err.log";
    # Local Network privacy needs a responsible app identity for login agents.
    ProgramArguments = lib.mkIf deskHost (lib.mkForce ["${macApp}/Contents/MacOS/lan-mouse" "daemon"]);
    AssociatedBundleIdentifiers = lib.optionals deskHost [macBundleId];
    # Keep the store dependencies alive and change the plist when a copied
    # binary or configuration changes, so Home Manager reloads the agent.
    EnvironmentVariables = lib.mkIf deskHost {
      LAN_MOUSE_PACKAGE = "${config.programs.lan-mouse.package}";
      LAN_MOUSE_CONFIG = "${config.xdg.configFile."lan-mouse/config.toml".source}";
      LAN_MOUSE_APP_INFO = "${macAppInfo}";
    };
  };
  home.activation.lanMouseApp =
    lib.mkIf (hostPlatform.isDarwin && deskHost)
    (lib.hm.dag.entryBetween ["setupLaunchAgents"] ["writeBoundary"] ''
      app=${lib.escapeShellArg macApp}
      $DRY_RUN_CMD mkdir -p "$app/Contents/MacOS" ${lib.escapeShellArg config.xdg.cacheHome}
      ${lib.optionalString (hostPlatform.system == "x86_64-darwin") ''
        # The upstream binary links against the libraries bundled next to it.
        releaseContents=${lib.escapeShellArg "${upstreamApp}/Applications/Lan Mouse.app/Contents"}
        $DRY_RUN_CMD cp -Rf "$releaseContents/Frameworks" "$releaseContents/Resources" "$app/Contents/"
        $DRY_RUN_CMD chmod -R u+w "$app/Contents/Frameworks" "$app/Contents/Resources"
      ''}
      # Copy the daemon so its executable belongs to the registered bundle.
      $DRY_RUN_CMD cp -f ${macBinary} "$app/Contents/MacOS/.lan-mouse.new"
      $DRY_RUN_CMD chmod 755 "$app/Contents/MacOS/.lan-mouse.new"
      $DRY_RUN_CMD mv -f "$app/Contents/MacOS/.lan-mouse.new" "$app/Contents/MacOS/lan-mouse"
      $DRY_RUN_CMD cp -f ${macAppInfo} "$app/Contents/Info.plist"
      $DRY_RUN_CMD /usr/bin/codesign --force --sign - --identifier ${macBundleId} "$app"
      $DRY_RUN_CMD /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
    '');
}
