## Grafana Alloy config (River syntax).
##
## Components:
##   - loki.source.journal      → tail systemd journal
##   - loki.relabel             → derive labels (unit, level, host, class)
##   - loki.write               → push to obs-host
##   - otelcol.receiver.otlp    → accept OTLP from local apps (DocAssist-LLM etc.)
##   - otelcol.exporter.otlp    → forward to obs-host's collector
##
## Generated as a writeText derivation so it can interpolate Nix config.
{
  cfg,
  pkgs,
  serverAddr,
}: let
  inherit (cfg) ports;
in
  pkgs.writeText "alloy-config.river" ''
    // ─── Logs: systemd journal → Loki ─────────────────────────────────────
    loki.source.journal "systemd" {
      max_age       = "24h"
      forward_to    = [loki.relabel.journal.receiver]
      relabel_rules = loki.relabel.journal.rules
      labels        = {
        host = "${"\${HOSTNAME}"}",
        job  = "systemd-journal",
      }
    }

    loki.relabel "journal" {
      forward_to = [loki.write.obs.receiver]

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "host"
      }
      rule {
        source_labels = ["__journal__transport"]
        target_label  = "transport"
      }
    }

    loki.write "obs" {
      endpoint {
        url = "http://${serverAddr}:${toString ports.loki}/loki/api/v1/push"
      }
      external_labels = {
        fleet = "OS-nixCfg",
      }
    }

    // ─── Traces: OTLP receiver → obs-host collector ──────────────────────
    otelcol.receiver.otlp "local" {
      grpc {
        endpoint = "127.0.0.1:4317"
      }
      http {
        endpoint = "127.0.0.1:4318"
      }
      output {
        traces  = [otelcol.processor.batch.local.input]
      }
    }

    otelcol.processor.batch "local" {
      output {
        traces = [otelcol.exporter.otlp.obs.input]
      }
    }

    otelcol.exporter.otlp "obs" {
      client {
        endpoint = "${serverAddr}:${toString ports.otelCollector}"
        tls {
          insecure = true
        }
      }
    }
  ''
