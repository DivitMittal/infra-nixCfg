## NixOS agent (also active on the server host — the obs-host scrapes itself).
##
## Runs on every NixOS host with `services.observability.role` ∈ {agent, server}:
##   - node_exporter (with textfile + systemd collectors)
##   - smartctl_exporter (drive health) — auto-skipped on VMs / WSL
##   - grafana-alloy (journald → Loki, plus an OTLP forwarder to the obs-host)
##   - nix-exporter timer (writes textfile metrics every 5 min)
##   - nixos-rebuild hook (emits rebuild durations)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.observability;
  inherit (cfg) ports;
  textfileDir = "/var/lib/observability/node-textfile";

  serverHost = lib.findFirst (h: h.name == cfg.serverHost) null cfg.fleet.hosts;
  serverAddr =
    if serverHost == null
    then "127.0.0.1"
    else serverHost.address;

  alloyConfig = import ../../../../lib/observability/alloy-config.nix {
    inherit cfg pkgs lib;
    inherit serverAddr textfileDir;
  };

  isAgentLike = cfg.enable && (cfg.role == "agent" || cfg.role == "server");
in {
  config = lib.mkIf isAgentLike {
    systemd.tmpfiles.rules = [
      "d /var/lib/observability 0755 root root - -"
      "d ${textfileDir} 0755 node-exporter node-exporter - -"
    ];

    services.prometheus.exporters.node = {
      enable = true;
      port = ports.nodeExporter;
      enabledCollectors = [
        "systemd"
        "processes"
        "filesystem"
        "loadavg"
        "meminfo"
        "netdev"
        "netstat"
        "diskstats"
        "cpu"
        "hwmon"
        "thermal_zone"
        "pressure"
        "textfile"
      ];
      extraFlags = [
        "--collector.textfile.directory=${textfileDir}"
        "--collector.systemd.unit-include=^(nixos-rebuild|sshd|systemd-networkd|NetworkManager|tailscaled|.+\\.timer|.+\\.service)$"
        "--collector.filesystem.fs-types-exclude=^(tmpfs|fuse\\..+|overlay|squashfs|nsfs|cgroup.*|proc|sys.*|devpts|mqueue|debugfs|tracefs|configfs|securityfs|pstore|bpf|autofs|binfmt_misc|hugetlbfs|ramfs|rpc_pipefs)$"
      ];
    };

    ## SMART drive health — skip on WSL (no underlying disk access)
    services.prometheus.exporters.smartctl = lib.mkIf (!(config ? wsl && config.wsl.enable or false)) {
      enable = true;
      port = 9633;
    };

    ## Grafana Alloy: journald → Loki, plus OTLP forwarder for app traces
    services.alloy = {
      enable = true;
      configPath = alloyConfig;
      extraFlags = [
        "--server.http.listen-addr=0.0.0.0:${toString ports.alloy}"
      ];
    };

    networking.firewall.allowedTCPPorts = [
      ports.nodeExporter
      9633 # smartctl_exporter
      ports.alloy
    ];
  };
}
