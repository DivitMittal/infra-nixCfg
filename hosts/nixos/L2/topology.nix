_: {
  # L2 registers itself (it's a nixosConfiguration), so it must not also be
  # declared by hand in flake/topology.nix: the two definitions conflict.
  topology.self = {
    # name defaults to config.networking.hostName

    hardware.info = "NixOS desktop (x86_64) - dual-boot with Windows 11 (L2-windows) — user: vanee";

    interfaces = {
      # Wired uplink to S1 (port3); S1 declares the edge from its side.
      eth0 = {
        network = "home";
        type = "ethernet";
      };
      wlan0 = {
        network = "home";
        type = "wireless";
      };
    };
  };
}
