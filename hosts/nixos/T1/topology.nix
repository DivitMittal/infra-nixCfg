_: {
  topology.self = {
    hardware.info = "HP t640 Thin Client (AMD Ryzen Embedded, x86_64) - PXE/netboot install via t1-netboot, hardware detected via nixos-facter. Edge router: hosts a multi-PPPoE OpenWrt/ImmortalWrt VM (macvtap passthrough of both physical NICs) — see router-vm.nix";

    # Best-effort until T1's real hardware/interface names are confirmed
    # (same caveat as router-vm.nix's placeholder physical NIC names).
    interfaces = {
      # WAN uplink, handed off into the router VM via macvtap passthrough.
      # No physicalConnections target exists for the ISP's modem/ONT — it's
      # outside this topology, same as VPS1/VPS2's plain "internet" interfaces.
      wan = {
        network = "internet";
        type = "wan";
      };

      # LAN uplink from the router VM's second macvtap interface into the
      # existing home switch/router.
      lan = {
        network = "home";
        physicalConnections = [
          {
            node = "router";
            interface = "lan";
          }
        ];
      };
    };
  };
}
