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
    # Live inventory on 2026-11-22 confirms 16 GiB installed (~13.6 GiB
    # OS-visible). This reservation was reduced during the former 4 GiB
    # configuration; retain the policy until host workloads are re-budgeted.
    extraKubeletConfig.systemReserved = {
      cpu = "500m";
      memory = "512Mi";
    };
  };
  networking.firewall.allowedTCPPorts = [6443];
}
