{
  writeShellApplication,
  symlinkJoin,
  lib,
  ...
}:
symlinkJoin {
  name = "kanata-tray-daemon";
  version = "1.0.0";

  paths = [
    (writeShellApplication {
      name = "kanata-tray-start";
      text = ''
        # Start kanata-tray and Karabiner daemon as background processes

        KARABINER_DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"

        # Set environment variables for kanata
        export KANATA_RSCROLL=1

        echo "Starting Karabiner VirtualHIDDevice Daemon..."
        if pgrep -f "Karabiner-VirtualHIDDevice-Daemon" >/dev/null; then
            echo "Karabiner daemon is already running"
        else
            sudo nohup "$KARABINER_DAEMON" >/dev/null 2>&1 &
            echo "Karabiner daemon started"
        fi

        echo "Starting kanata-tray..."
        if pgrep -f "kanata-tray" >/dev/null; then
            echo "kanata-tray is already running"
        else
            # Try to find kanata-tray in common locations
            KANATA_TRAY="$HOME/.nix-profile/bin/kanata-tray"

            if [ -z "$KANATA_TRAY" ]; then
                echo "Error: kanata-tray not found in PATH or nix store"
                exit 1
            fi

            sudo --preserve-env nohup "$KANATA_TRAY" >/dev/null 2>&1 &
            echo "kanata-tray started ($KANATA_TRAY)"
        fi

        echo "Both services started successfully!"
        echo "Use 'kanata-tray-stop' to stop them."
      '';
    })
    (writeShellApplication {
      name = "kanata-tray-stop";
      text = ''
        # Stop kanata-tray and Karabiner daemon processes.
        #
        # Two bugs fixed:
        #
        # 1. The original `pkill -f "kanata-tray"` matched this script's own
        #    command line (its path/name contains "kanata-tray"), so the script
        #    killed its own bash interpreter before reporting. `kanata-tray`
        #    fits in the 15-char process-name (`comm`) limit, so `-x` matches
        #    only the real binary and never this script.
        #
        # 2. `Karabiner-VirtualHIDDevice-Daemon` is 32 chars and exceeds the
        #    15-char `comm` limit, so `-x` cannot match it at all. Fall back to
        #    `-f` with a pattern that does not appear in this script's argv.

        kill_proc() {
          local flag="$1" name="$2"
          echo "Stopping ''${name}..."
          if ! pgrep "''${flag}" "''${name}" >/dev/null; then
            echo "''${name} is not running"
            return
          fi

          sudo pkill "''${flag}" "''${name}"
          # Graceful shutdown first; tray/daemon apps occasionally trap SIGTERM,
          # so escalate to SIGKILL if anything is still alive after a few seconds.
          for _ in 1 2 3 4 5; do
            pgrep "''${flag}" "''${name}" >/dev/null || break
            sleep 1
          done
          if pgrep "''${flag}" "''${name}" >/dev/null; then
            sudo pkill -9 "''${flag}" "''${name}"
          fi
          echo "''${name} stopped"
        }

        kill_proc -x "kanata-tray"
        kill_proc -f "Karabiner-VirtualHIDDevice-Daemon"

        echo "Both services stopped successfully!"
      '';
    })
  ];

  meta = {
    description = "Scripts to start/stop kanata-tray and Karabiner daemon as background processes on macOS";
    platforms = lib.platforms.darwin;
  };
}
