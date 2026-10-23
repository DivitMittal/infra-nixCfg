{
  writeShellApplication,
  symlinkJoin,
  lib,
  ...
}:
symlinkJoin {
  name = "wacom-toggle";
  version = "1.0.0";

  paths = [
    (writeShellApplication {
      name = "wacom-enable";
      text = ''
        # Loads Wacom services for the current session only.
        # Does NOT persist across reboots — run wacom-disable when done to keep
        # the disabled state clean (launchd won't auto-start these at next login).

        UID_CURRENT="$(id -u)"

        echo "Enabling Wacom services (session only)..."

        ## User (post-login)
        USER_AGENTS=(
          'com.wacom.DataStoreMgr'
          'com.wacom.wacomtablet'
        )
        for agent in "''${USER_AGENTS[@]}"; do
          if launchctl bootstrap gui/"''${UID_CURRENT}" "/Library/LaunchAgents/''${agent}.plist" 2>/dev/null; then
            echo "Bootstrap(User): ''${agent}"
          else
            echo "Already running(User): ''${agent}"
          fi
        done

        # IOManager label inside the plist is Wacom_IOManager, but the file is com.wacom.IOManager.plist
        if launchctl bootstrap gui/"''${UID_CURRENT}" /Library/LaunchAgents/com.wacom.IOManager.plist 2>/dev/null; then
          echo "Bootstrap(User): Wacom_IOManager"
        else
          echo "Already running(User): Wacom_IOManager"
        fi

        ## System
        SYSTEM_DAEMONS=(
          'com.wacom.UpdateHelper'
        )
        for daemon in "''${SYSTEM_DAEMONS[@]}"; do
          if sudo launchctl bootstrap system "/Library/LaunchDaemons/''${daemon}.plist" 2>/dev/null; then
            echo "Bootstrap(System): ''${daemon}"
          else
            echo "Already running(System): ''${daemon}"
          fi
        done

        echo "Wacom services loaded. Run wacom-disable when done to prevent autostart on next boot."
      '';
    })
    (writeShellApplication {
      name = "wacom-disable";
      text = ''
        # Stops Wacom services and marks them disabled in the launchd database.
        # Persists across reboots — services will NOT auto-start at next login/boot
        # unless wacom-enable is explicitly run again.

        UID_CURRENT="$(id -u)"

        echo "Disabling Wacom services..."

        ## User (post-login)
        USER_AGENTS=(
          'com.wacom.DataStoreMgr'
          'com.wacom.wacomtablet'
          'Wacom_IOManager'
        )
        for agent in "''${USER_AGENTS[@]}"; do
          if launchctl bootout gui/"''${UID_CURRENT}"/"''${agent}" 2>/dev/null; then
            echo "Bootout(User): ''${agent}"
          else
            echo "Already stopped(User): ''${agent}"
          fi
          launchctl disable gui/"''${UID_CURRENT}"/"''${agent}"
        done

        ## System
        SYSTEM_DAEMONS=(
          'com.wacom.UpdateHelper'
        )
        for daemon in "''${SYSTEM_DAEMONS[@]}"; do
          if sudo launchctl bootout system/"''${daemon}" 2>/dev/null; then
            echo "Bootout(System): ''${daemon}"
          else
            echo "Already stopped(System): ''${daemon}"
          fi
          sudo launchctl disable system/"''${daemon}"
        done

        echo "Wacom services disabled and will not autostart on next boot."
      '';
    })
  ];

  meta = {
    description = "Scripts to enable or disable Wacom tablet services on macOS";
    platforms = lib.platforms.darwin;
  };
}
