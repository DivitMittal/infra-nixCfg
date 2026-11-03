## Prometheus recording + alerting rules.
##
## Recording rules pre-compute fleet aggregates used by dashboards (cheaper than
## evaluating heavy queries at dashboard render time).
##
## Alerting rules are conservative — personal infra should not page constantly.
{pkgs}:
pkgs.writeText "rules.yaml" (builtins.toJSON {
  groups = [
    ## ─── Recording rules ────────────────────────────────────────────────
    {
      name = "fleet-aggregates";
      interval = "1m";
      rules = [
        {
          record = "fleet:hosts_up:count";
          expr = "count(up{job=\"node\"} == 1)";
        }
        {
          record = "fleet:hosts_down:count";
          expr = "count(up{job=\"node\"} == 0)";
        }
        {
          record = "fleet:systemd_failed_units:count";
          expr = "count by (instance) (node_systemd_unit_state{state=\"failed\"} == 1)";
        }
        {
          record = "fleet:nix_store_size_bytes:sum";
          expr = "sum by (instance) (nix_store_size_bytes)";
        }
      ];
    }

    ## ─── Critical alerts ────────────────────────────────────────────────
    {
      name = "fleet-critical";
      rules = [
        {
          alert = "HostDown";
          expr = "up{job=\"node\"} == 0";
          for = "5m";
          labels = {
            severity = "critical";
            host = "{{ $labels.instance }}";
          };
          annotations = {
            summary = "Host {{ $labels.instance }} is down";
            description = "node_exporter on {{ $labels.instance }} has been unreachable for 5m.";
          };
        }
        {
          alert = "DiskWillFillSoon";
          expr = ''
            predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.*|overlay"}[6h], 24*3600) < 0
            and on(instance, mountpoint) node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.*|overlay"} / node_filesystem_size_bytes < 0.15
          '';
          for = "15m";
          labels = {
            severity = "critical";
            host = "{{ $labels.instance }}";
          };
          annotations = {
            summary = "Disk on {{ $labels.instance }}:{{ $labels.mountpoint }} fills within 24h";
            description = "Linear extrapolation from the last 6h shows this mount running out within 24h.";
          };
        }
        {
          alert = "SystemdUnitFailed";
          expr = "node_systemd_unit_state{state=\"failed\"} == 1";
          for = "10m";
          labels = {
            severity = "critical";
            host = "{{ $labels.instance }}";
          };
          annotations = {
            summary = "{{ $labels.name }} failed on {{ $labels.instance }}";
            description = "systemd reports {{ $labels.name }} has been in failed state for 10m.";
          };
        }
        {
          alert = "CertExpiringSoon";
          expr = "probe_ssl_earliest_cert_expiry - time() < 14 * 24 * 3600";
          for = "1h";
          labels.severity = "critical";
          annotations = {
            summary = "Cert for {{ $labels.instance }} expires within 14 days";
            description = "Renew the certificate before it expires to avoid an outage.";
          };
        }
        {
          alert = "SmartPrefailure";
          expr = "smartctl_device_health_ok == 0";
          for = "30m";
          labels = {
            severity = "critical";
            host = "{{ $labels.instance }}";
          };
          annotations = {
            summary = "SMART pre-failure on {{ $labels.device }} ({{ $labels.instance }})";
            description = "Drive is reporting health != ok. Replace soon.";
          };
        }
      ];
    }

    ## ─── Warning alerts (digested) ──────────────────────────────────────
    {
      name = "fleet-warnings";
      rules = [
        {
          alert = "FlakeLockStale";
          expr = "nix_flake_lock_age_seconds > 14 * 24 * 3600";
          for = "1h";
          labels = {
            severity = "warning";
            host = "{{ $labels.instance }}";
          };
          annotations = {
            summary = "{{ $labels.instance }} flake.lock is older than 14 days";
            description = "Run `nix flake update` to pull recent inputs.";
          };
        }
        {
          alert = "NoRebuildRecently";
          expr = "(time() - nix_last_rebuild_timestamp_seconds) > 30 * 24 * 3600";
          for = "6h";
          labels = {
            severity = "warning";
            host = "{{ $labels.instance }}";
          };
          annotations = {
            summary = "{{ $labels.instance }} has not been rebuilt in 30+ days";
            description = "Likely missing kernel/security updates. Schedule a rebuild.";
          };
        }
        {
          alert = "MemoryPressureHigh";
          expr = "rate(node_pressure_memory_waiting_seconds_total[10m]) > 0.1";
          for = "15m";
          labels = {
            severity = "warning";
            host = "{{ $labels.instance }}";
          };
          annotations = {
            summary = "Memory pressure on {{ $labels.instance }}";
            description = "PSI memory.waiting rate > 0.1 — processes are stalling on RAM.";
          };
        }
        {
          alert = "NodeExporterRebuildSlow";
          expr = "histogram_quantile(0.95, rate(nixos_rebuild_duration_seconds_bucket[7d])) > 600";
          for = "1h";
          labels.severity = "warning";
          annotations = {
            summary = "Rebuilds are getting slower (P95 > 10 min over 7d)";
            description = "Consider running `nix-collect-garbage` or expanding binary cache coverage.";
          };
        }
        {
          alert = "BackupOlderThanWeek";
          expr = "(time() - node_systemd_timer_last_trigger_seconds{name=~\".*backup.*\"}) > 7 * 24 * 3600";
          for = "1h";
          labels = {
            severity = "warning";
            host = "{{ $labels.instance }}";
          };
          annotations.summary = "Backup timer {{ $labels.name }} on {{ $labels.instance }} has not fired in 7 days";
        }
      ];
    }
  ];
})
