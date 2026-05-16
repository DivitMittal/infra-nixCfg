## Nix-specific metrics emitter — the differentiator dashboard's data source.
##
## A systemd timer runs every 5 minutes and writes a `.prom` textfile that
## node_exporter ingests via its textfile collector.
##
## Metrics emitted:
##   nix_store_size_bytes
##   nix_store_paths_total
##   nix_gc_roots_total
##   nix_last_gc_timestamp_seconds
##   nix_last_rebuild_timestamp_seconds{flake_profile="…"}
##   nix_flake_lock_age_seconds
##   nix_generations_total{profile="…"}
##   nix_binary_cache_hit_ratio{cache="…"}
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.observability;
  textfileDir = "/var/lib/observability/node-textfile";
  flakeLockPath = "/etc/nixos/flake.lock"; # canonical fallback; the script also probes $HOME/Projects/OS-nixCfg/flake.lock

  script = pkgs.writeShellApplication {
    name = "nix-exporter";
    runtimeInputs = with pkgs; [coreutils gnused jq nix gawk findutils];
    text = ''
      set -euo pipefail
      OUT_TMP="$(mktemp -p ${textfileDir} nix-exporter.XXXXXX.prom.tmp)"
      OUT_FINAL="${textfileDir}/nix-exporter.prom"

      emit() {
        # Args: METRIC TYPE HELP VALUE [LABELS]
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

      ## Store size & path count via `nix path-info` (cheaper than `du`).
      if store_paths=$(nix --extra-experimental-features 'nix-command' path-info --json /run/current-system 2>/dev/null); then
        :
      fi
      store_root="/nix/store"
      size_bytes=$(du -sb "$store_root" 2>/dev/null | awk '{print $1}' || echo 0)
      path_count=$(find "$store_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
      emit nix_store_size_bytes  gauge "Total size of /nix/store in bytes."     "$size_bytes"
      emit nix_store_paths_total gauge "Number of top-level paths in /nix/store." "$path_count"

      ## GC roots — count of resolved gc-root symlinks.
      gc_roots=$(find /nix/var/nix/gcroots -mindepth 1 2>/dev/null | wc -l)
      emit nix_gc_roots_total gauge "Number of GC roots." "$gc_roots"

      ## Last GC: stored in /nix/var/nix/gc.lock mtime by convention, fall back to gcroots dir mtime.
      gc_file=/nix/var/nix/gc.lock
      if [[ -e "$gc_file" ]]; then
        last_gc=$(stat -c %Y "$gc_file")
        emit nix_last_gc_timestamp_seconds gauge "Unix time of the last `nix-collect-garbage` run." "$last_gc"
      fi

      ## Last system rebuild — current-system symlink mtime is the most reliable signal.
      if [[ -L /run/current-system ]]; then
        last_rebuild=$(stat -c %Y /run/current-system)
        emit nix_last_rebuild_timestamp_seconds gauge \
          "Unix time of the last system activation." \
          "$last_rebuild" 'flake_profile="system"'
      fi

      ## flake.lock age — try a couple of probable paths.
      for candidate in ${flakeLockPath} /home/*/Projects/OS-nixCfg/flake.lock /root/OS-nixCfg/flake.lock; do
        if [[ -e "$candidate" ]]; then
          lock_mtime=$(stat -c %Y "$candidate")
          now=$(date +%s)
          age=$(( now - lock_mtime ))
          emit nix_flake_lock_age_seconds gauge \
            "Age in seconds of flake.lock." \
            "$age" "path=\"$candidate\""
          break
        fi
      done

      ## Generations per profile.
      for profile_dir in /nix/var/nix/profiles /nix/var/nix/profiles/per-user/*; do
        [[ -d "$profile_dir" ]] || continue
        for profile in "$profile_dir"/*-link; do
          :
        done
      done
      for profile in /nix/var/nix/profiles/system /nix/var/nix/profiles/per-user/*/profile; do
        [[ -L "$profile" ]] || continue
        name=$(basename "$(dirname "$profile")")
        gen_count=$(find "$(dirname "$profile")" -maxdepth 1 -name "$(basename "$profile")-*-link" | wc -l)
        emit nix_generations_total gauge \
          "Number of generations retained for the given profile." \
          "$gen_count" "profile=\"$name\""
      done

      ## Atomic publish.
      mv "$OUT_TMP" "$OUT_FINAL"
    '';
  };
in {
  config = lib.mkIf (cfg.enable && (cfg.role == "agent" || cfg.role == "server")) {
    systemd.services.nix-exporter = {
      description = "Emit Nix metrics for node_exporter textfile collector";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${script}/bin/nix-exporter";
        ## Needs read access to /nix paths; runs as root for simplicity.
        User = "root";
      };
    };

    systemd.timers.nix-exporter = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "5m";
        Unit = "nix-exporter.service";
      };
    };
  };
}
