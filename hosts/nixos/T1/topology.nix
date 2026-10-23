_: {
  # nix-topology's self-registration (nixos/default.nix in the nix-topology
  # flake) keys each nixosConfiguration's self-topology node by
  # `config.topology.id`, which defaults to `config.networking.hostName` but
  # is an explicitly overridable `mkOption` ("Please overwrite it with a
  # unique identifier if your hostnames are not unique or don't reflect the
  # name you use to refer to that node.") — so a custom id IS supported.
  #
  # T1 now takes over R1's old router role entirely (see flake/topology.nix
  # nodes.R1's hardware.info), so register it under R1's old node id
  # ("router") instead of the default "T1". This means every existing
  # `physicalConnections = [{node = "router"; ...}]` reference on S1/ASL1/
  # windows-host/L2-windows (flake/topology.nix) now resolves to T1
  # automatically, with zero edits needed on those nodes' side.
  topology.id = "router";

  topology.self = {
    hardware.info = "HP t640 Thin Client (AMD Ryzen Embedded, x86_64) - PXE/netboot install via t1-netboot, hardware detected via nixos-facter. Edge router: hosts a multi-PPPoE OpenWrt/ImmortalWrt VM (macvtap passthrough of physical NICs) — see router-vm.nix";

    # Best-effort until T1's real hardware/interface names are confirmed —
    # same caveat as router-vm.nix's placeholder physical NIC names and
    # disko.nix's /dev/sda assumption. T1 needs at least 3 wired NICs (WAN,
    # S1 uplink, direct R1 link) plus a USB Wi-Fi adapter; whether the t640
    # actually has that many onboard/add-in ports, or some of these share a
    # link via VLANs on fewer physical NICs, is unconfirmed until the
    # hardware is in hand.
    interfaces = {
      # WAN uplink: R0 (now in bridge mode) passes the ISP's PPPoE session(s)
      # straight through to this NIC; the router VM terminates PPPoE itself
      # (macvtap passthrough — see router-vm.nix). Mirrors R1's old wan0
      # edge exactly, just moved to T1.
      wan = {
        network = "ont";
        type = "ethernet";
        physicalConnections = [
          {
            node = "r0";
            interface = "lan";
          }
        ];
      };

      # LAN uplink to S1 (same physical role R1's old lan0 had). No
      # physicalConnections needed here — S1.port1 already declares this
      # edge from its side (flake/topology.nix), and now resolves to this
      # node via the topology.id override above.
      lan0 = {
        network = "home";
        type = "ethernet";
      };

      # TP-Link dual-band USB Wi-Fi adapter attached to T1/the router VM,
      # configured 5GHz-only — the new AP for the devices that used to
      # associate to R1's Wi-Fi (ASL1, windows-host, L2-windows). No
      # physicalConnections needed here either, for the same reason as
      # lan0: those nodes already declare the other side of this edge.
      wlan = {
        network = "home";
        type = "wifi";
      };

      # New direct wired link to R1, now repurposed as a Kubernetes worker
      # node (flake/topology.nix nodes.R1) instead of a router.
      r1link = {
        network = "home";
        type = "ethernet";
      };

      # R1's old tailscale0 (hosts/openwrt/R1/modules/tailscale.nix) moves
      # here rather than to the new R1-as-k8s-worker node: every other
      # Tailscale usage in this repo (home/tty/network/vpn.nix,
      # home/gui/vpn.nix) is a per-user client, but R1's was the one
      # router-level instance — advertising/exit-noding the whole home LAN
      # over Tailscale. That's a function of *being the router*, which
      # transfers to T1 (and its T640 router VM) wholesale along with
      # wan/lan0/wlan above, not to R1's unrelated new k8s-worker role.
      tailscale0 = {
        network = "tailnet";
        type = "virtual";
        virtual = true;
      };
    };
  };
}
