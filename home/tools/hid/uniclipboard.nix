## UniClipboard: shared clipboard for the desk (L1, T2, and L2's Windows boot
## through hosts/win/L2/uniclipboard.nix). Pairing is a one-time, interactive
## step (`uniclip space invite` / `join`) and lives in each device's profile;
## see hosts/README.md.
{
  config,
  lib,
  hostPlatform,
  pkgs,
  ...
}: let
  package = pkgs.custom.uniclipboard-cli-bin;
  uniclip = "${package}/bin/uniclip";
  # Same desk as Lan Mouse. Other hosts get the CLI without a daemon.
  deskHost = builtins.elem config.hostSpec.hostName ["L1" "T2"];
  # The values `uniclip service start` writes into its own unit.
  environment = {
    PATH = "${package}/bin:/usr/bin:/bin";
    UNICLIPBOARD_ENV = "production";
    UC_CONSOLE_LOG = "off";
  };
in {
  home.packages = [package];

  # Bound to Sway like Lan Mouse: without a Wayland session there is no
  # clipboard to sync, and the daemon would start blind to it.
  systemd.user.services.uniclipboard = lib.mkIf (hostPlatform.isLinux && deskHost) {
    Unit = {
      Description = "UniClipboard clipboard sync";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${uniclip} run";
      Environment = lib.mapAttrsToList (name: value: "${name}=${value}") environment;
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["sway-session.target"];
  };

  launchd.agents.uniclipboard = lib.mkIf (hostPlatform.isDarwin && deskHost) {
    enable = true;
    config = {
      ProgramArguments = [uniclip "run"];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      EnvironmentVariables = environment;
      StandardOutPath = "${config.xdg.cacheHome}/uniclipboard.log";
      StandardErrorPath = "${config.xdg.cacheHome}/uniclipboard.err.log";
    };
  };

  # `uniclip service start` installs its own LaunchAgent pinned to one store
  # path, which breaks once that path is collected. Retire it before the
  # Home Manager agent loads; `uniclip run` refuses to start beside it.
  home.activation.retireUniclipService =
    lib.mkIf (hostPlatform.isDarwin && deskHost)
    (lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
      for plist in "$HOME"/Library/LaunchAgents/app.uniclipboard.cli.*.plist; do
        [ -e "$plist" ] || continue
        $DRY_RUN_CMD ${uniclip} service stop
        $DRY_RUN_CMD rm -f "$plist"
      done
    '');
}
