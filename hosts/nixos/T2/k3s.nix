_: {
  imports = [../_homelab/k3s.nix];

  services.k3s = {
    role = "agent";
    nodeName = "t2";
    nodeLabel = ["homelab-role=work"];
    serverAddr = "https://T3.lan:6443";
    # Leave capacity for Sway and API-backed agents. Reservations reduce pod
    # allocatable resources; they are not hard limits on host processes.
    extraKubeletConfig.systemReserved = {
      cpu = "1000m";
      memory = "2Gi";
    };
  };
}
