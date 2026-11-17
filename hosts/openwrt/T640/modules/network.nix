{lib, ...}: let
  inherit (lib.lists) range;
  inherit (lib.strings) fixedWidthString;
  inherit (lib.attrsets) listToAttrs nameValuePair;

  # Two upstream PPPoE lines: kmod-macvlan MAC-VLAN devices on top of a
  # shared WAN base device, one pppoe interface per line, load-balanced via
  # mwan3. This is the declarative nuci translation of the one-shot
  # `95-multi-pppoe` uci-defaults script that used to live in
  # flake/openwrt-images.nix (`mkMultiPppoeFiles`) — same MAC addresses,
  # device names, and mwan3 policy, just expressed as Nix-native `uci = {}`
  # like R1's modules instead of a shell heredoc. See hosts/README.md for the
  # multi-PPPoE background.
  pppoeLines = 2;
  lineNums = range 1 pppoeLines;

  # Guest-internal virtio-net naming follows PCI enumeration order, and
  # hosts/nixos/T1/router-vm.nix attaches the LAN macvtap first, so:
  #   eth0 = LAN downlink, already br-lan's port in the stock image.
  #   eth1 = WAN uplink, the shared base device the macvlan lines attach to.
  # Adjust if `ip link` inside the booted guest disagrees.
  wanBaseDevice = "eth1";

  # Home LAN, taken over from R1 (hosts/openwrt/R1/modules/network.nix).
  lanAddress = "192.168.2.1";

  # Locally-administered, unicast MAC addresses (IEEE 802: the "02"
  # first-octet prefix sets the U/L and I/G bits appropriately) for each
  # macvlan device — must be distinct from each other and from the base
  # device so the ISP's PPPoE/DHCP session tracking treats each line as a
  # separate client.
  macFor = n: "02:00:00:00:00:${fixedWidthString 2 "0" (toString n)}";

  wanmvName = n: "wanmv${toString n}";
  wanName = n: "wan${toString n}";
  memberName = n: "${wanName n}_m1_w3";

  wanmvDevices = listToAttrs (map (
      n:
        nameValuePair (wanmvName n) {
          _type = "device";
          type = "macvlan";
          ifname = wanBaseDevice;
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
          # PLACEHOLDER credentials — never committed for real, same
          # no-secrets-in-store convention as everywhere else in this repo.
          # A nuci reconcile.d hook (wan-credentials.nix) overwrites these
          # post-deploy with the real per-line username/password, decrypted
          # from infra-nixCfg-secrets at deploy time by
          # flake/openwrt-t640.nix's `set_wan_credentials` — mirroring how
          # R1's wifi-backup PSK is injected (hosts/openwrt/R1/modules/wifi-backup.nix).
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
    packages = [
      "kmod-macvlan"
      "mwan3"
      "luci-app-mwan3"
      "kmod-pppoe"
      "ppp-mod-pppoe"
    ];

    settings = {
      network = wanmvDevices // wanInterfaces;

      # Static leases carried over from R1, below the stock .100+ dynamic pool.
      dhcp = {
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
      };

      # mwan3: one interface + member per line, balanced (equal-weight)
      # policy by default. To switch to primary/backup failover instead,
      # give the backup line a higher metric (e.g. '2') than the primary
      # (metric '1') — see hosts/README.md.
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

    # Partial-field edits of sections this module doesn't fully own — the
    # stock generic-x86 image's default `lan` interface and its `@zone[1]`
    # wan firewall zone. Declaring these as typed `settings` sections would
    # silently drop whatever other fields the stock image ships them with
    # (nuci/openwrt-nix's docs: "once you define a section... all existing
    # values of this section are unset before applying the new values").
    # rawUci, by contrast, only ever touches the exact field named — same
    # reasoning as R1's cleanup.nix use of rawUci for one-off deletes.
    rawUci =
      [
        # The stock image runs a DHCP client (`wan`/`wan6`) on eth1; the
        # PPPoE lines replace it, so eth1 stays a bare base device.
        "uci -q delete network.wan || true"
        "uci -q delete network.wan6 || true"

        # Move the LAN onto the home subnet. A fresh guest is first deployed
        # at the stock 192.168.1.1; every later deploy targets this address.
        "uci set network.lan.ipaddr='${lanAddress}'"
        "uci set network.lan.netmask='255.255.255.0'"
        "uci commit network"

        # wan firewall zone: cover every pppoe interface (assumes the
        # default image ships firewall zones in the usual lan=0, wan=1
        # order).
        "uci del_list firewall.@zone[1].network='wan'"
        "uci del_list firewall.@zone[1].network='wan6'"
      ]
      ++ (map (n: "uci add_list firewall.@zone[1].network='${wanName n}'") lineNums)
      ++ ["uci commit firewall"];
  };
}
