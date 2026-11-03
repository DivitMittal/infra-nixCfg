## node_exporter on macOS, managed via launchd.
##
## Uses prometheus-node-exporter built for Darwin (available in nixpkgs).
## The textfile collector lives at ~/Library/Application Support/observability/textfile.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.observability;
  inherit (cfg) ports;
  textfileDir = "/Library/Application Support/observability/textfile";
in {
  config = lib.mkIf (cfg.enable && cfg.role == "agent") {
    launchd.daemons.node-exporter = {
      serviceConfig = {
        Label = "org.nixos.node-exporter";
        ProgramArguments = [
          "${pkgs.prometheus-node-exporter}/bin/node_exporter"
          "--web.listen-address=:${toString ports.nodeExporter}"
          "--collector.textfile.directory=${textfileDir}"
          "--collector.disable-defaults"
          ## macOS-relevant collectors
          "--collector.boottime"
          "--collector.cpu"
          "--collector.diskstats"
          "--collector.filesystem"
          "--collector.loadavg"
          "--collector.meminfo"
          "--collector.netdev"
          "--collector.os"
          "--collector.textfile"
          "--collector.time"
          "--collector.uname"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/node-exporter.out.log";
        StandardErrorPath = "/var/log/node-exporter.err.log";
      };
    };

    ## Ensure the textfile dir exists with sane perms before node_exporter starts.
    system.activationScripts.observabilityTextfileDir.text = ''
      mkdir -p "${textfileDir}"
      chmod 0755 "${textfileDir}"
    '';
  };
}
