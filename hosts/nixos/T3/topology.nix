_: {
  topology.self = {
    hardware.info = "HP t640 Thin Client (highest spec) - Linux GUI (Sway) + CPU AI inference (Ollama :11434)";
    interfaces.lan0 = {
      network = "home";
      type = "ethernet";
    };
    services.ollama = {
      name = "Ollama";
      info = "http://T3:11434";
    };
  };
}
