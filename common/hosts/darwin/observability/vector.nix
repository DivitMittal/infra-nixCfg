## Vector log shipper for macOS.
##
## Sources:
##   - macOS unified log (via `log show --predicate ... --style ndjson`, polled
##     by Vector's `exec` source on a 30s interval — sufficient for a personal box)
##   - launchd stdout/stderr files for our node-exporter / nix-exporter daemons
##
## Sink: Loki push API on the obs-host.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.observability;
  inherit (cfg) ports;

  serverHost = lib.findFirst (h: h.name == cfg.serverHost) null cfg.fleet.hosts;
  serverAddr =
    if serverHost == null
    then "127.0.0.1"
    else serverHost.address;

  hostname = config.networking.hostName;

  vectorTomlConfig = ''
    [sources.unified_log]
    type    = "exec"
    mode    = "scheduled"
    scheduled.exec_interval_secs = 30
    command = [
      "/usr/bin/log",
      "show",
      "--style", "ndjson",
      "--last", "30s",
      "--predicate", "subsystem != 'com.apple.duetactivityscheduler'"
    ]
    decoding.codec = "json"

    [sources.exporter_logs]
    type    = "file"
    include = ["/var/log/node-exporter.*.log", "/var/log/nix-exporter.*.log"]
    read_from = "end"

    [transforms.add_labels]
    type    = "remap"
    inputs  = ["unified_log", "exporter_logs"]
    source  = '''
      .host  = "${hostname}"
      .class = "darwin"
    '''

    [sinks.loki]
    type     = "loki"
    inputs   = ["add_labels"]
    endpoint = "http://${serverAddr}:${toString ports.loki}"
    encoding.codec = "json"
    labels = { host = "{{ host }}", class = "{{ class }}", job = "macos-log" }
  '';

  configFile = pkgs.writeText "vector.toml" vectorTomlConfig;
in {
  config = lib.mkIf (cfg.enable && cfg.role == "agent") {
    launchd.daemons.vector = {
      serviceConfig = {
        Label = "org.nixos.vector";
        ProgramArguments = [
          "${pkgs.vector}/bin/vector"
          "--config"
          "${configFile}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/vector.out.log";
        StandardErrorPath = "/var/log/vector.err.log";
      };
    };
  };
}
