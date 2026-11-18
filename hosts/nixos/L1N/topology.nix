_: {
  topology.self = {
    hardware.info = "NixOS on L1's T2-chip MacBook (x86_64) - triple-boot with L1 (macOS) & Windows 11 on same x86_64 hardware";

    interfaces = {
      wlan0 = {
        network = "home";
        type = "wireless";
      };
    };
  };
}
