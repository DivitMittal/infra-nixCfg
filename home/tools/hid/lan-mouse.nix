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
  macApp = "${config.home.homeDirectory}/Applications/Lan Mouse Desktop.app";
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
    package = inputs.lan-mouse.packages.${hostPlatform.system}.default.overrideAttrs (_: {
      buildInputs = [];
      # Disabling the GTK frontend must not also disable Linux input support.
      cargoBuildFlags = ["--no-default-features"] ++ lib.optionals hostPlatform.isLinux waylandFeatures;
      cargoTestFlags = ["--no-default-features"] ++ lib.optionals hostPlatform.isLinux waylandFeatures;
    });
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
      # Copy the native daemon so its executable belongs to the app bundle;
      # the GTK environment wrapper is unnecessary for this CLI-only build.
      $DRY_RUN_CMD cp -f ${config.programs.lan-mouse.package}/bin/.lan-mouse-wrapped "$app/Contents/MacOS/.lan-mouse.new"
      $DRY_RUN_CMD chmod 755 "$app/Contents/MacOS/.lan-mouse.new"
      $DRY_RUN_CMD mv -f "$app/Contents/MacOS/.lan-mouse.new" "$app/Contents/MacOS/lan-mouse"
      $DRY_RUN_CMD cp -f ${macAppInfo} "$app/Contents/Info.plist"
      $DRY_RUN_CMD /usr/bin/codesign --force --sign - --identifier ${macBundleId} "$app"
      $DRY_RUN_CMD /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
    '');
}
