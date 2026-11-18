_: {
  uci = {
    packages = ["qosify"];

    settings.qosify = {
      defaults = {
        _type = "defaults";
        defaults = ["/etc/qosify/*.conf"];
        dscp_prio = "video";
        dscp_icmp = "+besteffort";
        dscp_default_tcp = "besteffort";
        dscp_default_udp = "besteffort";
        prio_max_avg_pkt_len = "500";
      };

      besteffort = {
        _type = "class";
        ingress = "CS0";
        egress = "CS0";
      };

      bulk = {
        _type = "class";
        ingress = "LE";
        egress = "LE";
      };

      video = {
        _type = "class";
        ingress = "AF41";
        egress = "AF41";
      };

      voice = {
        _type = "class";
        ingress = "CS6";
        egress = "CS6";
      };

      wan = {
        _type = "interface";
        name = "wan";
        disabled = "0";
        # WAN rides the onboard 100M NIC (eth0, see network.nix), so the 10/100
        # link — not the ~110/105 fiber — is the bottleneck. Shape just below
        # 100M line rate so CAKE forms the queue here (and controls bufferbloat)
        # instead of overrunning the port. The margin also absorbs Ethernet
        # framing overhead, which qosify cannot express as SQM's per-packet
        # overhead.
        bandwidth_up = "95mbit";
        bandwidth_down = "95mbit";
        ingress = "1";
        egress = "1";
        mode = "diffserv4";
        nat = "1";
        host_isolate = "1";
        autorate_ingress = "0";
      };
    };

    files = [
      {
        path = "/etc/qosify/00-defaults.conf";
        content = ''
          # Latency-sensitive infrastructure
          tcp:22 voice
          tcp:5555 voice
          tcp:53 voice
          tcp:5353 voice
          udp:53 voice
          udp:5353 voice
          udp:123 voice

          # Interactive web traffic remains best effort
          tcp:80 +besteffort
          tcp:443 +besteffort
          udp:80 +besteffort
          udp:443 +besteffort
        '';
      }
      {
        path = "/etc/nuci/reconcile.d/30-qos";
        executable = true;
        content = ''
          #!/bin/sh
          set -eu

          if [ -x /etc/init.d/sqm ]; then
            /etc/init.d/sqm stop || true
            /etc/init.d/sqm disable || true
          fi
          if ip link show ifb4eth2 >/dev/null 2>&1; then
            ip link delete ifb4eth2
          fi

          service=/etc/init.d/qosify
          [ -x "$service" ] || {
            echo "qosify init service is unavailable" >&2
            exit 1
          }
          "$service" enable
          "$service" restart
        '';
      }
    ];
  };
}
