## Darwin observability — agent role only (servers run on NixOS).
##
## Provides:
##   - node_exporter via launchd (port 9100)
##   - nix-exporter shell timer (writes textfile metrics into the data dir)
##   - Vector for log shipping (unified log + nix-exporter textfile → obs-host Loki)
##
## Darwin can't use systemd-journal-upload (no journald) so Vector is the
## realistic choice for shipping `log show` output to Loki.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.observability;
in {
  imports = [
    ./node-exporter.nix
    ./nix-exporter.nix
    ./vector.nix
  ];

  config = lib.mkIf (cfg.enable && cfg.role == "agent") {
    assertions = [
      {
        assertion = lib.any (h: h.name == config.networking.hostName) cfg.fleet.hosts;
        message = "Darwin agent ${config.networking.hostName} must appear in services.observability.fleet.hosts.";
      }
    ];
  };
}
