## NixOS observability dispatcher
##
## Routes a host into either the `server` or `agent` implementation based on
## `services.observability.role`. The agent module is also imported on the
## server host (the server scrapes itself).
{
  config,
  lib,
  ...
}: let
  cfg = config.services.observability;
in {
  imports = [
    ./agent.nix
    ./server.nix
    ./nix-exporter.nix
    ./rebuild-hook.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.role != "none";
        message = "services.observability.enable = true requires role to be \"server\" or \"agent\".";
      }
      {
        assertion =
          cfg.role
          == "server"
          -> (lib.any (h: h.name == config.networking.hostName) cfg.fleet.hosts);
        message = ''
          The server host (${config.networking.hostName}) must appear in services.observability.fleet.hosts.
        '';
      }
    ];
  };
}
