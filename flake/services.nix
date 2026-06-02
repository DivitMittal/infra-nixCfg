## Local observability preview stack (services-flake / process-compose).
##
## Boots the full LGTM-A pipeline on the developer's laptop so you can iterate
## on dashboards, alert rules, and scrape configs without rebuilding L2. Reuses
## the same generators under `lib/observability/` so what runs locally and what
## runs on the obs-host stay in lock-step.
##
##   nix run .#observability     # interactive process-compose TUI
##
## Open http://127.0.0.1:3000 (admin / admin) once everything is healthy.
{
  inputs,
  lib,
  self,
  ...
}: {
  imports = [
    inputs.process-compose-flake.flakeModule
  ];

  perSystem = {pkgs, ...}: let
    libObs = self + "/lib/observability";
    dashboardsSrc = self + "/common/hosts/nixos/observability/dashboards";

    ## Synthetic `services.observability` cfg, scoped to the local box.
    ## Mirrors the option schema in common/hosts/all/observability/options.nix.
    cfg = {
      enable = true;
      role = "server";
      serverHost = "local";
      fleet.hosts = [
        {
          name = "local";
          address = "127.0.0.1";
          class =
            if pkgs.stdenvNoCC.hostPlatform.isDarwin
            then "darwin"
            else "nixos";
          labels = {};
        }
      ];
      ## Defaults from common/hosts/all/observability/options.nix.
      ports = {
        prometheus = 9090;
        grafana = 3000;
        loki = 3100;
        tempo = 3200;
        tempoOtlpGrpc = 4317;
        tempoOtlpHttp = 4318;
        alertmanager = 9093;
        nodeExporter = 9100;
        blackboxExporter = 9115;
        alloy = 12345;
        otelCollector = 4319;
      };
      ## Shorter retention for a laptop preview.
      retention = {
        metrics = "24h";
        logs = "12h";
        traces = "1h";
      };
      blackbox = {
        tcpTargets = [];
        httpsCertTargets = ["https://github.com" "https://grafana.com"];
        dnsTargets = ["github.com" "grafana.com"];
      };
      alerts = {
        ntfyTopic = null;
        discordWebhookEnvVar = "DISCORD_WEBHOOK";
      };
      secrets = {
        alertmanagerEnvFile = null;
        grafanaAdminPasswordFile = null;
      };
    };

    scrapeConfigs = import (libObs + "/prometheus-scrape-configs.nix") {inherit cfg lib;};
    rulesFile = import (libObs + "/prometheus-rules.nix") {inherit pkgs;};
    alertmanagerConfig = import (libObs + "/alertmanager-config.nix") {};
    otelcolConfig = import (libObs + "/otelcol-config.nix") {inherit cfg;};
    blackboxConfigFile = import (libObs + "/blackbox-config.nix") {inherit pkgs;};
    grafanaProvisioning = import (libObs + "/grafana-provisioning.nix") {
      inherit cfg pkgs dashboardsSrc;
    };

    yaml = pkgs.formats.yaml {};

    alertmanagerConfigFile = yaml.generate "alertmanager.yaml" alertmanagerConfig;
    otelcolConfigFile = yaml.generate "otelcol.yaml" otelcolConfig;
  in {
    process-compose."observability" = {
      imports = [
        inputs.services-flake.processComposeModules.default
      ];

      ## ─── Metrics ─────────────────────────────────────────────────────────
      services.prometheus."prom" = {
        port = cfg.ports.prometheus;
        listenAddress = "127.0.0.1";
        extraConfig = {
          global = {
            scrape_interval = "30s";
            evaluation_interval = "30s";
            external_labels.fleet = "OS-nixCfg-local";
          };
          scrape_configs = scrapeConfigs;
          rule_files = [(toString rulesFile)];
          alerting.alertmanagers = [
            {
              static_configs = [
                {targets = ["127.0.0.1:${toString cfg.ports.alertmanager}"];}
              ];
            }
          ];
        };
        extraFlags = [
          "--web.enable-remote-write-receiver"
          "--storage.tsdb.retention.time=${cfg.retention.metrics}"
        ];
      };

      ## ─── Logs ────────────────────────────────────────────────────────────
      ## services-flake's defaults already set server/common/schema_config to
      ## point at the per-instance dataDir; we only override retention here.
      services.loki."loki" = {
        httpAddress = "127.0.0.1";
        httpPort = cfg.ports.loki;
        extraConfig = {
          analytics.reporting_enabled = false;
          limits_config = {
            retention_period = cfg.retention.logs;
            reject_old_samples = true;
            reject_old_samples_max_age = "168h";
          };
        };
      };

      ## ─── Traces ──────────────────────────────────────────────────────────
      ## Default storage paths come from services-flake; we extend the OTLP
      ## listener config and wire the metrics-generator remote_write to prom.
      services.tempo."tempo" = {
        httpAddress = "127.0.0.1";
        httpPort = cfg.ports.tempo;
        extraConfig = {
          distributor.receivers.otlp.protocols = {
            grpc.endpoint = "0.0.0.0:${toString cfg.ports.tempoOtlpGrpc}";
            http.endpoint = "0.0.0.0:${toString cfg.ports.tempoOtlpHttp}";
          };
          compactor.compaction.block_retention = cfg.retention.traces;
          metrics_generator = {
            registry.external_labels.source = "tempo";
            storage.remote_write = [
              {
                url = "http://127.0.0.1:${toString cfg.ports.prometheus}/api/v1/write";
                send_exemplars = true;
              }
            ];
          };
          overrides.defaults.metrics_generator.processors = ["service-graphs" "span-metrics"];
          usage_report.reporting_enabled = false;
        };
      };

      ## ─── UI ──────────────────────────────────────────────────────────────
      services.grafana."grafana" = {
        http_port = cfg.ports.grafana;
        domain = "localhost";
        protocol = "http";
        extraConf = {
          security.admin_user = "admin";
          security.admin_password = "admin";
          analytics.reporting_enabled = false;
          log.level = "info";
        };
        ## Strip the apiVersion wrapper — services-flake adds it back.
        datasources = grafanaProvisioning.datasources.datasources;
        providers = grafanaProvisioning.dashboards.providers;
      };

      ## ─── Raw processes (no first-class services-flake module) ────────────
      settings.processes = {
        alertmanager = {
          command = pkgs.writeShellApplication {
            name = "start-alertmanager";
            runtimeInputs = [pkgs.prometheus-alertmanager];
            text = ''
              mkdir -p "''${DATA_DIR:-$PC_TEMP_DIR/alertmanager}"
              exec alertmanager \
                --config.file=${alertmanagerConfigFile} \
                --web.listen-address=127.0.0.1:${toString cfg.ports.alertmanager} \
                --storage.path="''${DATA_DIR:-$PC_TEMP_DIR/alertmanager}"
            '';
          };
          readiness_probe = {
            http_get = {
              host = "127.0.0.1";
              port = cfg.ports.alertmanager;
              path = "/-/ready";
            };
            initial_delay_seconds = 2;
            period_seconds = 10;
            failure_threshold = 5;
          };
          availability = {
            restart = "on_failure";
            max_restarts = 5;
          };
        };

        otelcol = {
          command = "${pkgs.opentelemetry-collector-contrib}/bin/otelcol-contrib --config=${otelcolConfigFile}";
          depends_on."tempo".condition = "process_healthy";
          ## otelcol's own self-metrics endpoint :8888 — confirms boot succeeded.
          readiness_probe = {
            http_get = {
              host = "127.0.0.1";
              port = 8888;
              path = "/metrics";
            };
            initial_delay_seconds = 5;
            period_seconds = 10;
            failure_threshold = 10;
          };
          availability = {
            restart = "on_failure";
            max_restarts = 5;
          };
        };

        blackbox = {
          command = ''
            ${pkgs.prometheus-blackbox-exporter}/bin/blackbox_exporter \
              --config.file=${blackboxConfigFile} \
              --web.listen-address=127.0.0.1:${toString cfg.ports.blackboxExporter}
          '';
          readiness_probe = {
            http_get = {
              host = "127.0.0.1";
              port = cfg.ports.blackboxExporter;
              path = "/-/healthy";
            };
            initial_delay_seconds = 2;
            period_seconds = 10;
            failure_threshold = 5;
          };
          availability = {
            restart = "on_failure";
            max_restarts = 5;
          };
        };

        node-exporter = {
          command = ''
            ${pkgs.prometheus-node-exporter}/bin/node_exporter \
              --web.listen-address=127.0.0.1:${toString cfg.ports.nodeExporter}
          '';
          readiness_probe = {
            http_get = {
              host = "127.0.0.1";
              port = cfg.ports.nodeExporter;
              path = "/metrics";
            };
            initial_delay_seconds = 2;
            period_seconds = 10;
            failure_threshold = 5;
          };
          availability = {
            restart = "on_failure";
            max_restarts = 5;
          };
        };
      };
    };
  };
}
