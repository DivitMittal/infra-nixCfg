_: {
  topology.self = {
    hardware.info = "NixOS T2 (x86_64) - triple-boot with L1 (macOS) & Windows 11 on same x86_64 hardware";

    interfaces = {
      wlan0 = {
        network = "home";
        type = "wireless";
      };
    };
  };
}
