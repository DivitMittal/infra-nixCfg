## Tempo single-binary configuration (filesystem backend).
##
## Receives OTLP both directly (for ad-hoc senders) and via the OTEL Collector
## (preferred — the collector tail-samples first).
{cfg}: let
  inherit (cfg) ports;
  stateDir = "/var/lib/observability/tempo";
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

  ## Tempo 3 dropped the ingester and compactor; retention is applied by the
  ## backend worker
  backend_worker.compaction = {
    block_retention = cfg.retention.traces;
    compacted_block_retention = "10m";
  };

  storage.trace = {
    backend = "local";
    local.path = "${stateDir}/blocks";
    wal.path = "${stateDir}/wal";
  };

  ## Tempo 3 components that otherwise default to /var/tempo
  live_store = {
    wal.path = "${stateDir}/live-store/traces";
    shutdown_marker_dir = "${stateDir}/live-store/shutdown-marker";
  };
  block_builder.wal.path = "${stateDir}/block-builder/traces";
  backend_scheduler.local_work_path = "${stateDir}/scheduler";

  metrics_generator = {
    registry.external_labels.source = "tempo";
    storage.path = "${stateDir}/generator";
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
