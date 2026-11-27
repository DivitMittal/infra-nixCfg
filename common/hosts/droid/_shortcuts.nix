_: {
  # Termux widget shortcuts — toggle Android developer settings & ADB
  home.file.".shortcuts/tasks/dev-on" = {
    executable = true;
    text = ''
      #!/system/bin/sh

      su -c '
      settings put global development_settings_enabled 1
      sleep 0.5
      settings put global adb_enabled 1
      sleep 0.2

      echo "development_settings_enabled=$(settings get global development_settings_enabled)"
      echo "adb_enabled=$(settings get global adb_enabled)"
      '
    '';
  };

  home.file.".shortcuts/tasks/dev-off" = {
    executable = true;
    text = ''
      #!/system/bin/sh

      su -c '
      settings put global adb_enabled 0
      sleep 0.2
      settings put global development_settings_enabled 0

      echo "development_settings_enabled=$(settings get global development_settings_enabled)"
      echo "adb_enabled=$(settings get global adb_enabled)"
      '
    '';
  };

  # adb over the LAN (port 5555) for nix-android, which drives the phone from a
  # controller while its only USB-C port holds the Ethernet adapter. Wireless
  # debugging can't stand in: it needs Wi-Fi. The persist. property makes adbd
  # listen again after a reboot. Connections still need an authorized adb key.
  home.file.".shortcuts/tasks/adb-tcp-on" = {
    executable = true;
    text = ''
      #!/system/bin/sh

      su -c '
      settings put global development_settings_enabled 1
      settings put global adb_enabled 1
      setprop persist.adb.tcp.port 5555
      setprop service.adb.tcp.port 5555
      setprop ctl.restart adbd
      sleep 1

      echo "adb_enabled=$(settings get global adb_enabled)"
      echo "persist.adb.tcp.port=$(getprop persist.adb.tcp.port)"
      '
    '';
  };

  home.file.".shortcuts/tasks/adb-tcp-off" = {
    executable = true;
    text = ''
      #!/system/bin/sh

      su -c '
      setprop persist.adb.tcp.port ""
      setprop service.adb.tcp.port -1
      setprop ctl.restart adbd
      sleep 1

      echo "persist.adb.tcp.port=$(getprop persist.adb.tcp.port)"
      '
    '';
  };
}
