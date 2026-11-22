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
    # T3 runs on a single 4 GB stick (~3.3 GB usable after the iGPU share)
    # until its failed 16 GB module is replaced; 1Gi here plus kubeReserved
    # and eviction left pods barely 1.3 GB. Raise this again with more RAM.
    extraKubeletConfig.systemReserved = {
      cpu = "500m";
      memory = "512Mi";
    };
  };
  networking.firewall.allowedTCPPorts = [6443];
}
