## L2 is the obs-host — runs the full server stack.
##
## Edit `fleet.hosts` to reflect actual hostnames/addresses (typically Tailscale).
## Edit `blackbox.httpsCertTargets` for any domains you self-host.
_: {
  services.observability = {
    enable = true;
    role = "server";
    serverHost = "L2";

    fleet.hosts = [
      {
        name = "L2";
        address = "127.0.0.1";
        class = "nixos";
      }
      {
        name = "T2";
        address = "t2";
        class = "nixos";
      }
      {
        name = "WSL";
        address = "wsl";
        class = "nixos";
      }
      {
        name = "L1";
        address = "l1";
        class = "darwin";
      }
      ## Droid (M1) typically not always-on; uncomment if/when you ship metrics from it.
      # { name = "M1"; address = "m1"; class = "droid"; }
    ];

    blackbox = {
      httpsCertTargets = [
        # "https://your-domain.example"
      ];
      dnsTargets = ["example.com" "github.com" "cachix.org"];
      tcpTargets = [
        {
          address = "T2";
          port = 22;
          description = "T2 ssh";
        }
        {
          address = "L1";
          port = 22;
          description = "L1 ssh";
        }
      ];
    };

    ## Wire these up by uncommenting + filling in the agenix secrets paths.
    # secrets = {
    #   alertmanagerEnvFile = config.age.secrets."observability/alertmanager.env".path;
    #   grafanaAdminPasswordFile = config.age.secrets."observability/grafana-admin".path;
    # };
  };
}
