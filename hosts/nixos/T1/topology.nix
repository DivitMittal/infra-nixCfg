_: {
  # nix-topology's self-registration (nixos/default.nix in the nix-topology
  # flake) keys each nixosConfiguration's self-topology node by
  # `config.topology.id`, which defaults to `config.networking.hostName` but
  # is an explicitly overridable `mkOption` ("Please overwrite it with a
  # unique identifier if your hostnames are not unique or don't reflect the
  # name you use to refer to that node.") — so a custom id IS supported.
  #
  # T1 now takes over R1's old router role entirely (see flake/topology.nix
  # comment above nodes.r0), so register it under R1's old node id
  # ("router") instead of the default "T1". This means every existing
  # `physicalConnections = [{node = "router"; ...}]` reference on S1/ASL1/
  # windows-host/L2-windows (flake/topology.nix) now resolves to T1
  # automatically, with zero edits needed on those nodes' side.
  topology.id = "router";

  topology.self = {
    hardware.info = "HP t640 Thin Client (AMD Ryzen Embedded, x86_64) - PXE/netboot install via t1-netboot, hardware detected via nixos-facter. Edge router: hosts an ImmortalWrt VM (DMZ behind R0 by default, multi-PPPoE optional) (macvtap passthrough of physical NICs) — see router-vm.nix";

    # Two wired NICs: the onboard port (LAN, to S1) and a USB 3 gigabit
    # adapter (WAN), plus a USB Wi-Fi adapter. Interface names in
    # router-vm.nix stay placeholders until `ip link` on the real box.
    interfaces = {
      # WAN uplink (USB 3 gigabit adapter): R0 (now in bridge mode) passes
      # the ISP's PPPoE session(s) straight through to this NIC; the router
      # VM terminates PPPoE itself (macvtap passthrough — see router-vm.nix).
      # Mirrors R1's old wan0 edge exactly, just moved to T1.
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

      # R1's old tailscale0 (hosts/openwrt/R1/modules/tailscale.nix) moves
      # here rather than to MON1 (the S100's new role): every other
      # Tailscale usage in this repo (home/tty/network/vpn.nix,
      # home/gui/vpn.nix) is a per-user client, but R1's was the one
      # router-level instance — advertising/exit-noding the whole home LAN
      # over Tailscale. That's a function of *being the router*, which
      # transfers to T1 (and its T640 router VM) wholesale along with
      # wan/lan0/wlan above.
      tailscale0 = {
        network = "tailnet";
        type = "virtual";
        virtual = true;
      };
    };
  };
}
