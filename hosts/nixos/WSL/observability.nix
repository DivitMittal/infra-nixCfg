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
        name = "WSL";
        address = "127.0.0.1";
        class = "nixos";
        labels.wsl = "true";
      }
    ];
  };
}
