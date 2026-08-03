{
  config,
  pkgs,
  ...
}: let
  home = config.user.home;
  shortcutsDir = "${home}/.shortcuts/tasks";
  script = name: text:
    pkgs.writeShellScript name ''
      #!/data/data/com.termux/files/usr/bin/sh
      ${text}
    '';
in {
  # Termux widget shortcuts — toggle Android developer settings & ADB.
  # The scripts live at ~/.shortcuts/tasks/<name> so Termux:Widget can pick
  # them up. We use `build.activation` (not `home.file`, which the pinned
  # nix-on-droid rev no longer supports) to install them on first activation.
  build.activation.shortcuts-setup = ''
    $DRY_RUN_CMD mkdir $VERBOSE_ARG -p "${shortcutsDir}"

    $VERBOSE_ECHO "Installing Termux:Widget shortcuts..."

    $DRY_RUN_CMD cp $VERBOSE_ARG \
      ${script "dev-on" ''
      su -c '
      settings put global development_settings_enabled 1
      sleep 0.5
      settings put global adb_enabled 1
      sleep 0.2

      echo "development_settings_enabled=$(settings get global development_settings_enabled)"
      echo "adb_enabled=$(settings get global adb_enabled)"
      '
    ''} "${shortcutsDir}/dev-on"
    $DRY_RUN_CMD chmod $VERBOSE_ARG +x "${shortcutsDir}/dev-on"

    $DRY_RUN_CMD cp $VERBOSE_ARG \
      ${script "dev-off" ''
      su -c '
      settings put global adb_enabled 0
      sleep 0.2
      settings put global development_settings_enabled 0

      echo "development_settings_enabled=$(settings get global development_settings_enabled)"
      echo "adb_enabled=$(settings get global adb_enabled)"
      '
    ''} "${shortcutsDir}/dev-off"
    $DRY_RUN_CMD chmod $VERBOSE_ARG +x "${shortcutsDir}/dev-off"
  '';
}
