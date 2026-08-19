_: {
  uci = {
    packages = ["tailscale"];

    settings = {
      network.tailscale = {
        _type = "interface";
        device = "tailscale0";
        proto = "none";
      };

      firewall = {
        zone = [
          {
            _type = "zone";
            name = "tailscale";
            network = ["tailscale"];
            input = "ACCEPT";
            output = "ACCEPT";
            forward = "ACCEPT";
          }
        ];

        forwarding = [
          {
            _type = "forwarding";
            src = "lan";
            dest = "tailscale";
          }
          {
            _type = "forwarding";
            src = "tailscale";
            dest = "lan";
          }
        ];
      };
    };

    files = [
      {
        path = "/etc/nuci/reconcile.d/50-tailscale";
        executable = true;
        content = ''
          #!/bin/sh
          set -eu

          service=/etc/init.d/tailscale
          [ -x "$service" ] || {
            echo "Tailscale init service is unavailable" >&2
            exit 1
          }
          "$service" enable
          "$service" running || "$service" start
        '';
      }
    ];
  };
}
