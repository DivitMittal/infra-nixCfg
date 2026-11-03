## Generates Prometheus scrape_configs from the declared fleet inventory.
##
## Jobs:
##   - node       : node_exporter on every host
##   - alloy      : Grafana Alloy's own metrics on every NixOS host
##   - blackbox-* : ICMP / TCP / HTTPS / DNS probes through blackbox_exporter
##   - self       : Prometheus, Grafana, Loki, Tempo, Alertmanager self-metrics
{
  cfg,
  lib,
}: let
  inherit (lib) optionals;
  inherit (cfg) ports;
  hosts = cfg.fleet.hosts;
  serverAddr =
    (lib.findFirst (h: h.name == cfg.serverHost) {address = "127.0.0.1";} hosts).address;

  mkTargets = port: hostsList:
    map (h: {
      targets = ["${h.address}:${toString port}"];
      labels =
        {
          instance = h.name;
          inherit (h) class;
        }
        // h.labels;
    })
    hostsList;

  icmpTargets = map (h: h.address) hosts;
  tcpTargets = map (t: "${t.address}:${toString t.port}") cfg.blackbox.tcpTargets;

  ## Relabeling shared by all blackbox jobs: target becomes a probe param,
  ## traffic is routed through blackbox_exporter on the obs-host.
  blackboxRelabel = [
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
      replacement = "${serverAddr}:${toString ports.blackboxExporter}";
    }
  ];

  mkBlackboxJob = name: module: targets: {
    job_name = "blackbox-${name}";
    metrics_path = "/probe";
    params.module = [module];
    static_configs = [{inherit targets;}];
    relabel_configs = blackboxRelabel;
  };
in
  [
    ## ─── Hosts ────────────────────────────────────────────────────────────
    {
      job_name = "node";
      static_configs = mkTargets ports.nodeExporter hosts;
    }
    {
      job_name = "alloy";
      static_configs = mkTargets ports.alloy (lib.filter (h: h.class == "nixos") hosts);
      metrics_path = "/metrics";
    }

    ## ─── Self-monitoring ──────────────────────────────────────────────────
    {
      job_name = "prometheus";
      static_configs = [{targets = ["127.0.0.1:${toString ports.prometheus}"];}];
    }
    {
      job_name = "grafana";
      static_configs = [{targets = ["127.0.0.1:${toString ports.grafana}"];}];
    }
    {
      job_name = "loki";
      static_configs = [{targets = ["127.0.0.1:${toString ports.loki}"];}];
    }
    {
      job_name = "tempo";
      static_configs = [{targets = ["127.0.0.1:${toString ports.tempo}"];}];
    }
    {
      job_name = "alertmanager";
      static_configs = [{targets = ["127.0.0.1:${toString ports.alertmanager}"];}];
    }
    {
      job_name = "otel-collector";
      static_configs = [{targets = ["127.0.0.1:8888"];}];
    }
  ]
  ## ─── Blackbox probes ────────────────────────────────────────────────────
  ++ optionals (icmpTargets != []) [(mkBlackboxJob "icmp" "icmp" icmpTargets)]
  ++ optionals (tcpTargets != []) [(mkBlackboxJob "tcp" "tcp_connect" tcpTargets)]
  ++ optionals (cfg.blackbox.httpsCertTargets != []) [
    (mkBlackboxJob "https" "https_2xx" cfg.blackbox.httpsCertTargets)
  ]
  ++ optionals (cfg.blackbox.dnsTargets != []) [
    (mkBlackboxJob "dns" "dns_a" cfg.blackbox.dnsTargets)
  ]
