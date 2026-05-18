## macOS nix-exporter — variant of the NixOS script.
##
## Differences vs. NixOS:
##   - uses BSD `stat -f %m` instead of GNU `stat -c %Y`
##   - profile location is `~/.local/state/nix/profiles` (nix-darwin) or
##     `/nix/var/nix/profiles/per-user/$user`
##   - last-rebuild signal: nix-darwin's `/run/current-system` doesn't exist;
##     fall back to `/var/run/current-system` (`/etc/static`)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.observability;
  textfileDir = "/Library/Application Support/observability/textfile";

  script = pkgs.writeShellApplication {
    name = "nix-exporter-darwin";
    runtimeInputs = with pkgs; [coreutils gnused jq nix gawk findutils];
    text = ''
      set -euo pipefail
      OUT_TMP=$(mktemp -t nix-exporter.XXXXXX)
      OUT_FINAL="${textfileDir}/nix-exporter.prom"

      emit() {
        local metric="$1" mtype="$2" help="$3" value="$4" labels="''${5:-}"
        {
          echo "# HELP $metric $help"
          echo "# TYPE $metric $mtype"
          if [[ -n "$labels" ]]; then
            echo "$metric{$labels} $value"
          else
            echo "$metric $value"
          fi
        } >>"$OUT_TMP"
      }

      bsd_mtime() { stat -f %m "$1"; }

      ## Store size
      size_bytes=$(/usr/bin/du -sk /nix/store 2>/dev/null | awk '{print $1 * 1024}')
      path_count=$(/usr/bin/find /nix/store -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
      emit nix_store_size_bytes  gauge "Total size of /nix/store in bytes." "$size_bytes"
      emit nix_store_paths_total gauge "Number of /nix/store paths."        "$path_count"

      ## GC roots
      gc_roots=$(/usr/bin/find /nix/var/nix/gcroots -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
      emit nix_gc_roots_total gauge "Number of GC roots." "$gc_roots"

      ## Last system activation — nix-darwin writes /run/current-system
      for candidate in /run/current-system /var/run/current-system; do
        if [[ -L "$candidate" ]]; then
          last_rebuild=$(bsd_mtime "$candidate")
          emit nix_last_rebuild_timestamp_seconds gauge \
            "Unix time of the last nix-darwin activation." \
            "$last_rebuild" 'flake_profile="system"'
          break
        fi
      done

      ## flake.lock age — search the user's projects dir
      for candidate in /Users/*/OS-nixCfg/flake.lock /Users/*/Projects/OS-nixCfg/flake.lock; do
        if [[ -e "$candidate" ]]; then
          lock_mtime=$(bsd_mtime "$candidate")
          now=$(date +%s)
          age=$(( now - lock_mtime ))
          emit nix_flake_lock_age_seconds gauge \
            "Age in seconds of flake.lock." \
            "$age" "path=\"$candidate\""
          break
        fi
      done

      mv "$OUT_TMP" "$OUT_FINAL"
    '';
  };
in {
  config = lib.mkIf (cfg.enable && cfg.role == "agent") {
    launchd.daemons.nix-exporter = {
      serviceConfig = {
        Label = "org.nixos.nix-exporter";
        ProgramArguments = ["${script}/bin/nix-exporter-darwin"];
        StartInterval = 300; # every 5 minutes
        RunAtLoad = true;
        StandardOutPath = "/var/log/nix-exporter.out.log";
        StandardErrorPath = "/var/log/nix-exporter.err.log";
      };
    };
  };
}
