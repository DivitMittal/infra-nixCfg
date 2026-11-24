{
  config,
  lib,
  pkgs,
  ...
}: let
  user = config.system.primaryUser;
  # The bundle and agent are installed separately by Home Manager.
  app = "${config.hostSpec.home}/Applications/Lan Mouse Desktop.app";
  bundleId = "org.divitmittal.lan-mouse";
  tcc = lib.getExe pkgs.customDarwin.tccutil;
in {
  # ASL1 imports these services too, but does not participate in this desk.
  system.activationScripts.postActivation.text = lib.mkIf (config.hostSpec.hostName == "L1") ''
    if [[ -d ${lib.escapeShellArg app} ]]; then
      echo ">> lan-mouse: syncing Accessibility TCC grant..."
      if /usr/bin/codesign --verify -R=${lib.escapeShellArg ''identifier "${bundleId}"''} ${lib.escapeShellArg app} \
        && ${tcc} -s kTCCServiceAccessibility -i ${bundleId} -e ${bundleId}; then
        lan_mouse_uid=$(/usr/bin/id -u ${lib.escapeShellArg user})
        lan_mouse_job="gui/$lan_mouse_uid/org.nix-community.home.lan-mouse"
        if /bin/launchctl print "$lan_mouse_job" >/dev/null 2>&1; then
          /bin/launchctl kickstart -k "$lan_mouse_job" \
            || echo "   warning: could not restart the Lan Mouse agent" >&2
        fi
      else
        echo "   warning: could not grant Lan Mouse Accessibility; check System Settings." >&2
      fi
    fi
  '';
}
