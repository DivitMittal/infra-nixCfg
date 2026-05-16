## Records nixos-rebuild duration into the textfile collector.
##
## Approach: a systemd `nixos-rebuild-wrapper@.service` template that wraps the
## activation script, timing it via $SECONDS, and writes the duration into a
## .prom textfile. This is the agent-side counterpart to the
## `nixos_rebuild_duration_seconds` recording rule.
##
## In practice you invoke this manually: `systemctl start nixos-rebuild-wrapper@switch.service`
## or wrap it in a small shell alias. It is intentionally NOT auto-running.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.observability;
  textfileDir = "/var/lib/observability/node-textfile";

  ## A small writeShellApplication that performs `nixos-rebuild $action` and times it.
  hookScript = pkgs.writeShellApplication {
    name = "nixos-rebuild-timed";
    runtimeInputs = with pkgs; [coreutils nixos-rebuild];
    text = ''
      set -euo pipefail
      action="''${1:-switch}"
      flake="''${2:-/etc/nixos}"

      start=$(date +%s)
      status="success"
      if ! nixos-rebuild "$action" --flake "$flake"; then
        status="failure"
      fi
      end=$(date +%s)
      duration=$(( end - start ))

      OUT="${textfileDir}/nixos-rebuild.prom"
      TMP=$(mktemp -p ${textfileDir} nixos-rebuild.XXXXXX.tmp)
      {
        echo "# HELP nixos_rebuild_duration_seconds Last nixos-rebuild duration."
        echo "# TYPE nixos_rebuild_duration_seconds gauge"
        echo "nixos_rebuild_duration_seconds{action=\"$action\",status=\"$status\"} $duration"

        echo "# HELP nixos_rebuild_timestamp_seconds Unix timestamp of the last nixos-rebuild run."
        echo "# TYPE nixos_rebuild_timestamp_seconds gauge"
        echo "nixos_rebuild_timestamp_seconds{action=\"$action\",status=\"$status\"} $end"

        ## Histogram bucket emission (manual — only one observation, but lets
        ## Prometheus aggregate quantiles via the recording rule.)
        for bucket in 30 60 120 300 600 1200 2400; do
          if (( duration <= bucket )); then val=1; else val=0; fi
          echo "nixos_rebuild_duration_seconds_bucket{action=\"$action\",le=\"$bucket\"} $val"
        done
        echo "nixos_rebuild_duration_seconds_bucket{action=\"$action\",le=\"+Inf\"} 1"
        echo "nixos_rebuild_duration_seconds_count{action=\"$action\"} 1"
        echo "nixos_rebuild_duration_seconds_sum{action=\"$action\"} $duration"
      } >"$TMP"
      mv "$TMP" "$OUT"

      [[ "$status" == "success" ]] || exit 1
    '';
  };
in {
  config = lib.mkIf (cfg.enable && (cfg.role == "agent" || cfg.role == "server")) {
    environment.systemPackages = [hookScript];

    systemd.services."nixos-rebuild-wrapper@" = {
      description = "Timed nixos-rebuild (%i = action: switch|boot|test|dry-build)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hookScript}/bin/nixos-rebuild-timed %i";
        User = "root";
      };
    };
  };
}
