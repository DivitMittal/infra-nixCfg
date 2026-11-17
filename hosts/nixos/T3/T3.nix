# T3 — the highest-spec t640: Linux GUI box and the home lab's main AI node.
# The Sway session comes from the shared desktop layer (common/hosts/nixos/
# desktop.nix lists T3) and the full home-manager profile (home/default.nix).
_: {
  # Vega 3 iGPU: needed for the Sway session (and Vulkan, if ever tried for
  # inference).
  hardware.graphics.enable = true;

  # CPU inference only — the t640 has no dGPU, so stick to small models
  # (roughly <=8B at Q4) and give the box as much RAM as it takes.
  # Listens on the LAN so T4 and the workstations can offload to it.
  services.ollama = {
    enable = true;
    host = "0.0.0.0";
    port = 11434;
    openFirewall = true;
  };
}
