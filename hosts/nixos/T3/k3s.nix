_: {
  imports = [../_homelab/k3s.nix];

  services.k3s = {
    role = "server";
    nodeName = "t3";
    nodeLabel = ["homelab-role=services"];
    # One server with SQLite: intentionally non-HA, no embedded etcd.
    clusterInit = false;
    extraFlags = ["--tls-san=T3.lan"];
    # NodePort is sufficient; avoid reserving host ports 80/443 for Traefik.
    disable = ["traefik" "servicelb"];
    extraKubeletConfig.systemReserved = {
      cpu = "500m";
      memory = "1Gi";
    };
  };
  networking.firewall.allowedTCPPorts = [6443];
}
