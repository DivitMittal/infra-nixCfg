# R0 remains opt-in until its identity, SNMP version and ACL are verified.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.r0Snmp;
in {
  options.homelab.r0Snmp.encryptedConfig = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Agenix-encrypted complete snmp_exporter YAML with auths.r0 and modules.r0; null disables polling.";
  };
  config = lib.mkIf (cfg.encryptedConfig != null) {
    age.secrets.r0-snmp = {
      file = cfg.encryptedConfig;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    services.prometheus.exporters.snmp = {
      enable = true;
      listenAddress = "127.0.0.1";
      openFirewall = false;
      configurationPath = "/run/credentials/prometheus-snmp-exporter.service/r0";
      # The upstream build-time checker copies string paths into the store.
      enableConfigCheck = false;
    };
    systemd.services.prometheus-snmp-exporter.serviceConfig.LoadCredential = [
      "r0:${config.age.secrets.r0-snmp.path}"
    ];
    services.prometheus.scrapeConfigs = [
      {
        job_name = "snmp-r0";
        scrape_interval = "60s";
        scrape_timeout = "15s";
        metrics_path = "/snmp";
        params = {
          auth = ["r0"];
          module = ["r0"];
          target = ["192.168.1.1"];
        };
        static_configs = [
          {
            targets = ["127.0.0.1:9116"];
            labels.device = "R0";
          }
        ];
        relabel_configs = [
          {
            target_label = "instance";
            replacement = "192.168.1.1";
          }
        ];
      }
    ];
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "R0 SNMP";
        options.path = pkgs.writeTextDir "r0-snmp.json" (builtins.toJSON {
          title = "R0 SNMP";
          uid = "homelab-r0-snmp";
          schemaVersion = 39;
          refresh = "1m";
          time = {
            from = "now-6h";
            to = "now";
          };
          panels = lib.imap0 (i: panel:
            panel
            // {
              id = i + 1;
              type = "timeseries";
              datasource = "Prometheus";
              gridPos = {
                x = 0;
                y = i * 8;
                w = 24;
                h = 8;
              };
            }) [
            {
              title = "Scrape availability";
              targets = [{expr = "up{job=\"snmp-r0\"}";}];
            }
            {
              title = "Interface receive bits/s";
              targets = [{expr = "rate(ifHCInOctets{job=\"snmp-r0\"}[5m]) * 8";}];
            }
            {
              title = "Interface transmit bits/s";
              targets = [{expr = "rate(ifHCOutOctets{job=\"snmp-r0\"}[5m]) * 8";}];
            }
            {
              title = "Interface errors/s";
              targets = [{expr = "rate(ifInErrors{job=\"snmp-r0\"}[5m]) + rate(ifOutErrors{job=\"snmp-r0\"}[5m])";}];
            }
          ];
        });
      }
    ];
  };
}
