{
  lib,
  wanMode,
  homelab,
  ...
}: let
  inherit (lib.lists) range optionals;
  inherit (lib.strings) fixedWidthString;
  inherit (lib.attrsets) listToAttrs nameValuePair optionalAttrs;

  # Two WAN modes (flake/openwrt-t640.nix builds both):
  #   "dmz"   — default. R0 (the ISP router) stays in router mode and
  #             DMZ-forwards everything to this router's static WAN address.
  #   "pppoe" — R0 in bridge mode; this router dials two PPPoE lines itself
  #             and balances them with mwan3.
  isPppoe = wanMode == "pppoe";

  # Guest-internal virtio-net naming follows PCI enumeration order, and
  # hosts/nixos/T1/router-vm.nix attaches the LAN macvtap first, so:
  #   eth0 = LAN downlink, already br-lan's port in the stock image.
  #   eth1 = WAN uplink.
  # Adjust if `ip link` inside the booted guest disagrees.
  wanDevice = "eth1";

  # Home LAN, taken over from R1 (hosts/openwrt/R1/modules/network.nix).
  # Also baked into the image (flake/openwrt-images.nix), because a stock
  # image's 192.168.1.1 LAN would collide with R0's subnet in DMZ mode.
  lanAddress = "192.168.2.1";

  # DMZ mode: the address R0 forwards to. Same values R1 used behind the
  # same R0. Set R0's DMZ host to this address.
  dmzWan = {
    _type = "interface";
    device = wanDevice;
    proto = "static";
    ipaddr = "192.168.1.254";
    netmask = "255.255.255.0";
    gateway = "192.168.1.1";
    dns = [
      "192.168.1.1"
      "1.1.1.1"
    ];
  };

  # ── PPPoE mode ─────────────────────────────────────────────────────────
  # kmod-macvlan MAC-VLAN devices on top of the WAN device, one pppoe
  # interface per line, load-balanced via mwan3. See hosts/README.md.
  pppoeLines = 2;
  lineNums = range 1 pppoeLines;

  # Locally-administered unicast MACs, distinct per line so the ISP's PPPoE
  # session tracking treats each line as a separate client.
  macFor = n: "02:00:00:00:00:${fixedWidthString 2 "0" (toString n)}";

  wanmvName = n: "wanmv${toString n}";
  wanName = n: "wan${toString n}";
  memberName = n: "${wanName n}_m1_w3";

  wanmvDevices = listToAttrs (map (
      n:
        nameValuePair (wanmvName n) {
          _type = "device";
          type = "macvlan";
          ifname = wanDevice;
          name = wanmvName n;
          macaddr = macFor n;
        }
    )
    lineNums);

  wanInterfaces = listToAttrs (map (
      n:
        nameValuePair (wanName n) {
          _type = "interface";
          proto = "pppoe";
          device = wanmvName n;
          ipv6 = "auto";
          # Placeholders only. wan-credentials.nix overwrites them with the
          # real per-line login, injected at deploy time from
          # infra-nixCfg-secrets.
          username = "CHANGEME-line${toString n}-username";
          password = "CHANGEME-line${toString n}-password";
        }
    )
    lineNums);

  mwan3Interfaces = listToAttrs (map (
      n:
        nameValuePair (wanName n) {
          _type = "interface";
          enabled = "1";
          family = "ipv4";
          reliability = "1";
          count = "1";
          timeout = "2";
          interval = "5";
          down = "3";
          up = "3";
        }
    )
    lineNums);

  mwan3Members = listToAttrs (map (
      n:
        nameValuePair (memberName n) {
          _type = "member";
          interface = wanName n;
          metric = "1";
          weight = "3";
        }
    )
    lineNums);
in {
  uci = {
    packages = optionals isPppoe [
      "kmod-macvlan"
      "mwan3"
      "luci-app-mwan3"
      "kmod-pppoe"
      "ppp-mod-pppoe"
    ];

    settings =
      {
        network =
          if isPppoe
          then wanmvDevices // wanInterfaces
          else {wan = dmzWan;};

        # Static leases carried over from R1, below the stock .100+ dynamic pool.
        dhcp = {
          S1 = {
            _type = "host";
            name = "S1";
            mac = homelab.macs.S1;
            ip = "192.168.2.2";
          };
          usb_eth = {
            _type = "host";
            name = "usb-eth";
            mac = homelab.macs.usb-eth;
            ip = "192.168.2.4";
          };
        };
      }
      // optionalAttrs isPppoe {
        # Balanced (equal-weight) by default. For primary/backup failover,
        # give the backup line a higher metric — see hosts/README.md.
        mwan3 =
          mwan3Interfaces
          // mwan3Members
          // {
            balanced = {
              _type = "policy";
              use_member = map memberName lineNums;
            };

            default_rule = {
              _type = "rule";
              dest_ip = "0.0.0.0/0";
              use_policy = "balanced";
            };
          };
      };

    # Partial-field edits of sections this module doesn't fully own (the
    # stock `lan` interface and the `@zone[1]` wan firewall zone). Typed
    # `settings` sections replace a section wholesale; rawUci touches only
    # the named field.
    rawUci =
      [
        # IPv6 from R0 isn't routed to a DMZ host, and PPPoE brings its own,
        # so the stock DHCPv6 client goes in both modes.
        "uci -q delete network.wan6 || true"
      ]
      ++ optionals isPppoe [
        # The PPPoE lines replace the stock DHCP `wan` on eth1.
        "uci -q delete network.wan || true"
      ]
      ++ [
        "uci set network.lan.ipaddr='${lanAddress}'"
        "uci set network.lan.netmask='255.255.255.0'"
        "uci commit network"

        # Assumes the stock lan=0, wan=1 firewall zone order.
        "uci del_list firewall.@zone[1].network='wan6'"
      ]
      ++ optionals isPppoe (
        ["uci del_list firewall.@zone[1].network='wan'"]
        ++ map (n: "uci add_list firewall.@zone[1].network='${wanName n}'") lineNums
      )
      ++ ["uci commit firewall"];
  };
}
