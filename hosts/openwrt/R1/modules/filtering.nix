_: {
  uci = {
    packages = ["adblock"];

    settings = {
      adblock.global = {
        _type = "adblock";
        adb_enabled = "1";
        adb_debug = "0";
        adb_nftforce = "0";
        adb_dnsshift = "0";
        adb_safesearch = "1";
        adb_backup = "0";
        adb_mail = "0";
        adb_report = "0";
        adb_feed = [
          "adguard"
          "adguard_tracking"
          "certpl"
          "doh_blocklist"
          "oisd_nsfw"
        ];
      };

      firewall = {
        force_lan_dns = {
          _type = "redirect";
          name = "Force LAN DNS through R1";
          src = "lan";
          src_dport = "53";
          dest_port = "53";
          proto = ["tcp" "udp"];
          target = "DNAT";
          family = "any";
        };

        force_tailscale_dns = {
          _type = "redirect";
          name = "Force Tailscale DNS through R1";
          src = "tailscale";
          src_dport = "53";
          dest_port = "53";
          proto = ["tcp" "udp"];
          target = "DNAT";
          family = "any";
        };

        block_lan_dot = {
          _type = "rule";
          name = "Block LAN DNS over TLS";
          src = "lan";
          dest = "wan";
          dest_port = "853";
          proto = ["tcp" "udp"];
          target = "REJECT";
          family = "any";
        };

        block_tailscale_dot = {
          _type = "rule";
          name = "Block Tailscale DNS over TLS";
          src = "tailscale";
          dest = "wan";
          dest_port = "853";
          proto = ["tcp" "udp"];
          target = "REJECT";
          family = "any";
        };
      };
    };

    files = [
      {
        path = "/etc/nuci/reconcile.d/40-adblock";
        executable = true;
        content = ''
          #!/bin/sh
          set -eu

          service=/etc/init.d/adblock
          [ -x "$service" ] || {
            echo "adblock init service is unavailable" >&2
            exit 1
          }
          "$service" enable
          "$service" running || "$service" start
        '';
      }
    ];
  };
}
