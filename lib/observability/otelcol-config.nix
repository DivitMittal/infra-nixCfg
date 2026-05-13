## OpenTelemetry Collector — ingress for OTLP from agents.
##
## Pipeline:
##   receivers: otlp (gRPC + HTTP)
##   processors:
##     batch          : amortize export overhead
##     memory_limiter : drop spans before OOM
##     tail_sampling  : keep errors + slow spans, drop the boring 95%
##   exporters: otlp/tempo (gRPC to local Tempo)
##
## Self-metrics on :8888 are scraped by Prometheus (job `otel-collector`).
{cfg}: let
  inherit (cfg) ports;
in {
  receivers.otlp.protocols = {
    grpc.endpoint = "0.0.0.0:${toString ports.otelCollector}";
    http.endpoint = "0.0.0.0:${toString (ports.otelCollector + 1)}";
  };

  processors = {
    batch = {
      timeout = "5s";
      send_batch_size = 8192;
    };
    memory_limiter = {
      check_interval = "1s";
      limit_mib = 512;
      spike_limit_mib = 128;
    };
    tail_sampling = {
      decision_wait = "10s";
      num_traces = 50000;
      expected_new_traces_per_sec = 10;
      policies = [
        {
          name = "errors";
          type = "status_code";
          status_code.status_codes = ["ERROR"];
        }
        {
          name = "slow-traces";
          type = "latency";
          latency.threshold_ms = 500;
        }
        {
          name = "sample-baseline";
          type = "probabilistic";
          probabilistic.sampling_percentage = 5;
        }
      ];
    };
  };

  exporters."otlp/tempo" = {
    endpoint = "127.0.0.1:${toString ports.tempoOtlpGrpc}";
    tls.insecure = true;
  };

  service = {
    telemetry.metrics.address = "0.0.0.0:8888";
    pipelines.traces = {
      receivers = ["otlp"];
      processors = ["memory_limiter" "tail_sampling" "batch"];
      exporters = ["otlp/tempo"];
    };
  };
}
