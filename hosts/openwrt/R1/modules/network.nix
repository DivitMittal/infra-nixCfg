{wanMode, ...}: let
  isAndroidTether = wanMode == "android-tether";
  isWifiBackup = wanMode == "wifi-backup";
in {
  uci = {
    packages = [
      "kmod-usb-net"
      # Both USB gigabit adapters (lan0 + wan0) are Realtek RTL8153.
      "kmod-usb-net-rtl8152"
      # Onboard RTL8105e (eth0) is now an untagged LAN access port.
      "kmod-r8169"
    ];

    settings = {
      # NICs are pinned to stable names by MAC in netnames.nix:
      #   lan0 = USB RTL8153 → S1 port1 (flat LAN + management path)
      #   wan0 = USB RTL8153 → R0 (WAN)
      #   eth0 = onboard RTL8105e → untagged LAN access port
      network = {
        loopback = {
          _type = "interface";
          device = "lo";
          proto = "static";
          ipaddr = "127.0.0.1";
          netmask = "255.0.0.0";
        };

        # LAN bridge: the USB-gigabit link to S1 (lan0) joined with the onboard
        # 100M NIC (eth0) as a second untagged access port. S1 is a flat,
        # untagged LAN now — no VLAN tagging on this link (see
        # hosts/switch/S1/default.nix). The Wi-Fi AP will attach here later
        # (network = "lan" on its wifi-iface).
        br_lan = {
          _type = "device";
          type = "bridge";
          name = "br-lan";
          ports = [
            "lan0"
            "eth0"
          ];
        };

        wan =
          {_type = "interface";}
          // (
            if isAndroidTether
            then {
              # Fallback path independent of the WAN GbE: a phone tethered over
              # USB presents as an RNDIS/CDC device (usb0). Survives wan0/R0
              # issues. Confirm the actual device name when tethering.
              device = "usb0";
              proto = "dhcp";
            }
            else if isWifiBackup
            then {
              # Fallback path over Wi-Fi: R1's RTL8188EU associates to R0's
              # own network (see wifi-backup.nix) as a station. No `device`
              # here — netifd attaches the wireless netdev automatically via
              # the wifi-iface's `network = "wan"` binding.
              proto = "dhcp";
            }
            else {
              # Normal path: dedicated USB-gigabit uplink (wan0) → R0.
              device = "wan0";
              proto = "static";
              ipaddr = "192.168.1.254";
              netmask = "255.255.255.0";
              gateway = "192.168.1.1";
              dns = [
                "192.168.1.1"
                "1.1.1.1"
              ];
            }
          );

        wan6 = {
          _type = "interface";
          device = "@wan";
          proto = "dhcpv6";
        };

        lan = {
          _type = "interface";
          device = "br-lan";
          proto = "static";
          ipaddr = "192.168.2.1";
          netmask = "255.255.255.0";
        };
      };

      dhcp = {
        lan = {
          _type = "dhcp";
          interface = "lan";
          start = "100";
          limit = "100";
          leasetime = "12h";
          ignore = "0";
        };

        # TP-Link TL-SG105E managed switch — pin its mgmt IP via DHCP so it
        # stays reachable at a known address (below the .100-.199 dynamic pool).
        S1 = {
          _type = "host";
          name = "S1";
          mac = "ac:a7:f1:aa:2b:12";
          ip = "192.168.2.2";
        };

        M1 = {
          _type = "host";
          name = "M1";
          mac = "9c:69:d3:7f:90:de";
          ip = "192.168.2.4";
        };

        # L1's former reservation (00:e0:4c:55:34:28) is gone: that adapter is
        # now R1's own wan0 NIC. Re-add L1 here once its real LAN MAC is known.
      };

      firewall = {
        zone = [
          {
            _type = "zone";
            name = "lan";
            network = ["lan"];
            input = "ACCEPT";
            output = "ACCEPT";
            forward = "ACCEPT";
          }
          {
            _type = "zone";
            name = "wan";
            network = ["wan" "wan6"];
            input = "REJECT";
            output = "ACCEPT";
            forward = "REJECT";
            masq = "1";
            mtu_fix = "1";
          }
        ];

        forwarding = [
          {
            _type = "forwarding";
            src = "lan";
            dest = "wan";
          }
        ];
      };
    };
  };
}
