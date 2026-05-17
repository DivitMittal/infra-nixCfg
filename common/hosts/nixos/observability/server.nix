## NixOS observability server (role = "server")
##
## Brings up the LGTM-A stack:
##   - Prometheus       (metrics)
##   - Loki             (logs)
##   - Tempo            (traces; receiver wired but no traced services yet)
##   - Grafana          (UI, datasources + dashboards provisioned as code)
##   - Alertmanager     (routing → ntfy + Discord)
##   - OTEL Collector   (OTLP ingress with tail-sampling → Tempo)
##   - blackbox_exporter (network mesh probes)
##
## All data dirs live under /var/lib/observability/. Open ports are listed
## at the bottom of `config`. State retention is configurable per-pillar.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.observability;
  inherit (cfg) ports;

  libObs = ../../../../lib/observability;

  scrapeConfigs = import (libObs + "/prometheus-scrape-configs.nix") {inherit cfg lib;};
  rulesFile = import (libObs + "/prometheus-rules.nix") {inherit pkgs cfg;};

  blackboxConfig = import (libObs + "/blackbox-config.nix") {inherit pkgs;};
  blackboxTargets = import (libObs + "/blackbox-targets.nix") {inherit cfg lib;};

  lokiConfig = import (libObs + "/loki-config.nix") {inherit cfg pkgs;};
  tempoConfig = import (libObs + "/tempo-config.nix") {inherit cfg pkgs;};
  otelcolConfig = import (libObs + "/otelcol-config.nix") {inherit cfg pkgs;};
  alertmanagerConfig = import (libObs + "/alertmanager-config.nix") {inherit cfg pkgs;};

  grafanaProvisioning = import (libObs + "/grafana-provisioning.nix") {
    inherit cfg pkgs;
    dashboardsSrc = ./dashboards;
  };
in {
  config = lib.mkIf (cfg.enable && cfg.role == "server") {
    ## Persistent state lives under a single root for easy backups.
    systemd.tmpfiles.rules = [
      "d /var/lib/observability 0750 root root - -"
      "d /var/lib/observability/prometheus 0750 prometheus prometheus - -"
      "d /var/lib/observability/loki 0750 loki loki - -"
      "d /var/lib/observability/tempo 0750 tempo tempo - -"
      "d /var/lib/observability/grafana 0750 grafana grafana - -"
      "d /var/lib/observability/alertmanager 0750 alertmanager alertmanager - -"
    ];

    ## Prometheus
    services.prometheus = {
      enable = true;
      port = ports.prometheus;
      retentionTime = cfg.retention.metrics;
      stateDir = "observability/prometheus";
      globalConfig = {
        scrape_interval = "30s";
        evaluation_interval = "30s";
        external_labels = {
          fleet = "OS-nixCfg";
        };
      };
      inherit scrapeConfigs;
      ruleFiles = [rulesFile];
      alertmanagers = [
        {
          static_configs = [
            {
              targets = ["127.0.0.1:${toString ports.alertmanager}"];
            }
          ];
        }
      ];
    };

    ## blackbox_exporter — network mesh, cert expiry, DNS
    services.prometheus.exporters.blackbox = {
      enable = true;
      port = ports.blackboxExporter;
      configFile = blackboxConfig;
    };

    ## Loki
    services.loki = {
      enable = true;
      configuration = lokiConfig;
      dataDir = "/var/lib/observability/loki";
    };

    ## Tempo — bind to all interfaces so fleet agents can push OTLP
    services.tempo = {
      enable = true;
      settings = tempoConfig;
    };

    ## OTEL Collector — ingress with tail-sampling, fan-out to Tempo
    services.opentelemetry-collector = {
      enable = true;
      settings = otelcolConfig;
    };

    ## Alertmanager
    services.prometheus.alertmanager = {
      enable = true;
      port = ports.alertmanager;
      configuration = alertmanagerConfig;
      ## Decrypt notifier secrets at activation time, expose as env to alertmgr.
      environmentFile =
        if cfg.secrets.alertmanagerEnvFile != null
        then toString cfg.secrets.alertmanagerEnvFile
        else null;
    };

    ## Grafana — dashboards + datasources provisioned from Nix
    services.grafana = {
      enable = true;
      dataDir = "/var/lib/observability/grafana";
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = ports.grafana;
          domain = config.networking.hostName;
          root_url = "http://${config.networking.hostName}:${toString ports.grafana}/";
        };
        security =
          {
            admin_user = "admin";
          }
          // lib.optionalAttrs (cfg.secrets.grafanaAdminPasswordFile != null) {
            admin_password = "$__file{${toString cfg.secrets.grafanaAdminPasswordFile}}";
          };
        analytics.reporting_enabled = false;
        log.level = "info";
      };
      provision = {
        enable = true;
        datasources.settings = grafanaProvisioning.datasources;
        dashboards.settings = grafanaProvisioning.dashboards;
      };
    };

    ## Fleet-level blackbox targets (consumed by the scrape job)
    services.observability._blackboxTargets = blackboxTargets;

    networking.firewall.allowedTCPPorts = [
      ports.prometheus
      ports.grafana
      ports.loki
      ports.tempo
      ports.tempoOtlpGrpc
      ports.tempoOtlpHttp
      ports.alertmanager
      ports.otelCollector
      ports.blackboxExporter
    ];
  };

  ## Internal-only option used to thread blackbox targets into the scrape job.
  options.services.observability._blackboxTargets = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    internal = true;
  };
}
