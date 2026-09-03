_: {
  # Termux widget shortcuts — toggle Android developer settings & ADB
  home.file.".shortcuts/tasks/dev-on" = {
    executable = true;
    text = ''
      #!/data/data/com.termux/files/usr/bin/sh

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
      #!/data/data/com.termux/files/usr/bin/sh

      su -c '
      settings put global adb_enabled 0
      sleep 0.2
      settings put global development_settings_enabled 0

      echo "development_settings_enabled=$(settings get global development_settings_enabled)"
      echo "adb_enabled=$(settings get global adb_enabled)"
      '
    '';
  };
}
