## Loki single-binary configuration with BoltDB-shipper + filesystem chunks.
## Adequate for a personal fleet. Swap to S3 if/when retention exceeds local disk.
{cfg}: let
  inherit (cfg) ports;
  retentionHours = "${cfg.retention.logs}"; # passed verbatim to limits_config
in {
  auth_enabled = false;

  server = {
    http_listen_port = ports.loki;
    grpc_listen_port = 9096;
    log_level = "info";
  };

  common = {
    path_prefix = "/var/lib/observability/loki";
    storage.filesystem = {
      chunks_directory = "/var/lib/observability/loki/chunks";
      rules_directory = "/var/lib/observability/loki/rules";
    };
    replication_factor = 1;
    ring.kvstore.store = "inmemory";
  };

  schema_config.configs = [
    {
      from = "2024-01-01";
      store = "tsdb";
      object_store = "filesystem";
      schema = "v13";
      index = {
        prefix = "index_";
        period = "24h";
      };
    }
  ];

  limits_config = {
    retention_period = retentionHours;
    ingestion_rate_mb = 16;
    ingestion_burst_size_mb = 32;
    max_streams_per_user = 0;
    reject_old_samples = true;
    reject_old_samples_max_age = "168h";
  };

  compactor = {
    working_directory = "/var/lib/observability/loki/compactor";
    retention_enabled = true;
    delete_request_store = "filesystem";
    retention_delete_delay = "2h";
    compaction_interval = "10m";
  };

  ## Ruler (alerts on logs) — disabled by default; alerts run from Prometheus.
  ruler.storage = {
    type = "local";
    local.directory = "/var/lib/observability/loki/rules";
  };

  analytics.reporting_enabled = false;
}
