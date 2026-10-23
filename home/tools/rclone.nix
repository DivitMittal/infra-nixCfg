{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: let
  remotesPath = "${config.home.homeDirectory}/mnt";

  # Cloud storage mount options (Google Drive, Dropbox, etc.)
  # Optimized for write-heavy usage with aggressive caching
  cloudMountOpts = ''
    --vfs-cache-max-size 50G \
    --vfs-cache-max-age 48h \
    --dir-cache-time 5m \
    --poll-interval 1m \
    --vfs-read-chunk-size 1M \
    --buffer-size 32M \
    --vfs-read-ahead 128M \
    --vfs-write-back 1m \
    --attr-timeout 1s \
    --no-modtime \
    --vfs-cache-mode full \
    --log-level ERROR \
    --no-unicode-normalization=false
  '';

  # FTP mount options
  # Lighter caching since FTP has lower latency than cloud APIs
  # Shorter timeouts for fresher directory listings
  # No write-back delay - FTP handles writes directly
  ftpMountOpts = ''
    --vfs-cache-max-size 5G \
    --vfs-cache-max-age 1h \
    --dir-cache-time 30s \
    --poll-interval 30s \
    --vfs-read-chunk-size 512K \
    --buffer-size 16M \
    --vfs-read-ahead 32M \
    --vfs-write-back 0s \
    --attr-timeout 1s \
    --vfs-cache-mode writes \
    --log-level ERROR \
    --ftp-concurrency 4
  '';

  mkRcloneMountScript = remoteName:
    pkgs.writeShellScriptBin remoteName ''
      #!/usr/bin/env bash

      # Log start time
      echo "Script started at $(date)"

      # Check if rclone is installed
      if ! command -v rclone &> /dev/null; then
        echo "rclone could not be found. Please install it."
        exit 1
      fi

      # Check if the remote specified exists
      if ! rclone lsd "${remoteName}:" &> /dev/null; then
        echo "The specified remote '${remoteName}' does not exist or is not accessible."
        mkdir -p "${remotesPath}/${remoteName}"
        exit 1
      fi

      # Check if there is any connectivity
      if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo "No network connectivity."
        exit 1
      fi

      cleanup() {
        echo "Cleaning up and exiting..."
        exit 0
      }

      # Trap SIGINT and SIGTERM
      trap cleanup SIGINT SIGTERM

      # Detect remote type and select appropriate mount options
      REMOTE_TYPE=$(rclone config show "${remoteName}" 2>/dev/null | grep "^type" | cut -d'=' -f2 | tr -d ' ')

      case "$REMOTE_TYPE" in
        ftp|sftp)
          echo "Detected FTP/SFTP remote, using lightweight cache settings"
          MOUNT_OPTS="${ftpMountOpts}"
          ;;
        *)
          echo "Detected cloud remote ($REMOTE_TYPE), using full cache settings"
          MOUNT_OPTS="${cloudMountOpts}"
          ;;
      esac

      rclone mount $MOUNT_OPTS "${remoteName}:" "${remotesPath}/${remoteName}"
    '';
in {
  imports = [
    inputs.infra-nixCfg-secrets.homeManagerModules.rclone
    inputs.infra-nixCfg-secrets.homeManagerConfigurations.rcloneAccounts
  ];

  home.packages = lib.attrsets.attrValues ({
      inherit (pkgs) rclone;
    }
    // (lib.attrsets.genAttrs config.programs.rclone.remotesList mkRcloneMountScript));
}
