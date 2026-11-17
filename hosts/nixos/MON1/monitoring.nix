# Light monitoring stack sized for the S100's 2 GiB: Prometheus + blackbox
# probes + Grafana. The heavier log/trace pieces (Loki/Tempo, PR #36) are
# meant for T3 instead.
#
# Coverage limits worth knowing:
#   - S1 (TP-Link TL-SG105E "Easy Smart") has no SNMP, so it is only
#     ping/HTTP-probed, not scraped for port counters.
#   - The unmanaged switch can't be monitored at all; it shows up indirectly,
#     through probes of whatever is plugged into it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # T1's host address is static (hosts/nixos/T1/router-vm.nix). The others
  # take DHCP leases from the router, whose dnsmasq answers for `<host>.lan`.
  nodeTargets = [
    "192.168.2.3:9100" # T1
    "T2.lan:9100"
    "T3.lan:9100"
    "localhost:9100" # MON1
  ];

  pingTargets = [
    "192.168.2.1" # T640 router guest
    "192.168.2.2" # S1 managed switch
    "1.1.1.1" # internet, via whichever PPPoE line mwan3 picks
    "8.8.8.8"
  ];

  httpTargets = [
    "http://192.168.2.1" # router LuCI
    "http://192.168.2.2" # S1 web UI
    "http://T3.lan:31200" # RSSHub
  ];

  # Probe through blackbox: the probed address goes in as a URL parameter and
  # the exporter itself is what Prometheus actually connects to.
  blackboxJob = name: module: targets: {
    job_name = name;
    metrics_path = "/probe";
    params.module = [module];
    static_configs = [{inherit targets;}];
    relabel_configs = [
      {
        source_labels = ["__address__"];
        target_label = "__param_target";
      }
      {
        source_labels = ["__param_target"];
        target_label = "instance";
      }
      {
        target_label = "__address__";
        replacement = "localhost:${toString config.services.prometheus.exporters.blackbox.port}";
      }
    ];
  };

  grafanaSecretDir = "/var/lib/grafana-secrets";
in {
  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "30d";
    globalConfig.scrape_interval = "30s";

    exporters.blackbox = {
      enable = true;
      port = 9115;
      configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
        modules = {
          icmp = {
            prober = "icmp";
            timeout = "5s";
          };
          http_2xx = {
            prober = "http";
            timeout = "5s";
          };
        };
      });
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{targets = nodeTargets;}];
      }
      (blackboxJob "ping" "icmp" pingTargets)
      (blackboxJob "http" "http_2xx" httpTargets)
    ];
  };

  # Neither secret may live in the repo or the Nix store, so both are
  # generated on the box on first start and read back by Grafana at runtime.
  # Admin password: `sudo cat /var/lib/grafana-secrets/admin-password`.
  systemd.services.grafana-secrets = {
    description = "Generate Grafana's secret key and admin password";
    wantedBy = ["grafana.service"];
    before = ["grafana.service"];
    serviceConfig.Type = "oneshot";
    path = [pkgs.openssl pkgs.coreutils];
    script = ''
      install -d -m 0700 -o grafana -g grafana ${grafanaSecretDir}
      for f in secret-key admin-password; do
        if [ ! -s ${grafanaSecretDir}/$f ]; then
          openssl rand -hex 24 > ${grafanaSecretDir}/$f
          chown grafana:grafana ${grafanaSecretDir}/$f
          chmod 0400 ${grafanaSecretDir}/$f
        fi
      done
    '';
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
      security = {
        secret_key = "$__file{${grafanaSecretDir}/secret-key}";
        admin_password = "$__file{${grafanaSecretDir}/admin-password}";
      };
      analytics.reporting_enabled = false;
    };
    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        url = "http://localhost:${toString config.services.prometheus.port}";
        isDefault = true;
      }
    ];
  };

  # Firewall is off in the common layer; these only matter if it's enabled.
  networking.firewall.allowedTCPPorts = lib.mkIf config.networking.firewall.enable [
    3000
    config.services.prometheus.port
  ];
}
