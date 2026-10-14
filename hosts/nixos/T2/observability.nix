_: {
  services.observability = {
    enable = true;
    role = "agent";
    serverHost = "L2";
    fleet.hosts = [
      {
        name = "L2";
        address = "l2";
        class = "nixos";
      }
      {
        name = "T2";
        address = "127.0.0.1";
        class = "nixos";
      }
    ];
  };
}
