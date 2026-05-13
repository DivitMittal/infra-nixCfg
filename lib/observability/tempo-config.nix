## Tempo single-binary configuration (filesystem backend).
##
## Receives OTLP both directly (for ad-hoc senders) and via the OTEL Collector
## (preferred — the collector tail-samples first).
{cfg}: let
  inherit (cfg) ports;
in {
  server = {
    http_listen_port = ports.tempo;
    grpc_listen_port = 9095;
    log_level = "info";
  };

  distributor.receivers.otlp.protocols = {
    grpc.endpoint = "0.0.0.0:${toString ports.tempoOtlpGrpc}";
    http.endpoint = "0.0.0.0:${toString ports.tempoOtlpHttp}";
  };

  ingester = {
    max_block_duration = "5m";
    trace_idle_period = "10s";
  };

  compactor.compaction = {
    block_retention = cfg.retention.traces;
    compacted_block_retention = "10m";
  };

  storage.trace = {
    backend = "local";
    local.path = "/var/lib/observability/tempo/blocks";
    wal.path = "/var/lib/observability/tempo/wal";
  };

  metrics_generator = {
    registry.external_labels.source = "tempo";
    storage.path = "/var/lib/observability/tempo/generator";
    storage.remote_write = [
      {
        url = "http://127.0.0.1:${toString ports.prometheus}/api/v1/write";
        send_exemplars = true;
      }
    ];
  };

  overrides.defaults.metrics_generator.processors = ["service-graphs" "span-metrics"];

  usage_report.reporting_enabled = false;
}
