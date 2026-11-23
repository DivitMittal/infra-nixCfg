_: {
  topology.self = {
    hardware.info = "WSL2 NixOS inside L2's Windows install - evaluates nix-win's winConfigurations.l2";
    interfaces.eth0 = {
      network = "wsl";
      type = "virtual";
      virtual = true;
      physicalConnections = [
        {
          node = "L2-windows";
          interface = "wsl0";
        }
      ];
    };
  };
}
