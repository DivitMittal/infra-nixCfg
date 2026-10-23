_: {
  topology.self = {
    # name defaults to config.networking.hostName

    hardware.info = "NixOS (x86_64) - bootstrapped via nixos-iso on x86_64-darwin hardware";

    interfaces = {
      wlan0 = {
        network = "home";
        type = "wireless";
      };
    };
  };
}
