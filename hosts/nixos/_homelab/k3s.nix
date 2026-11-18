# Imported only by the two compute hosts; the router and MON1 stay external.
{
  config,
  inputs,
  ...
}: {
  # agenix and its identity path come from _homelab/base.nix.
  age.secrets.k3s-token = {
    file = inputs.infra-nixCfg-secrets + "/secrets/homelab/k3s-token.age";
    mode = "0400";
  };

  services.k3s = {
    enable = true;
    tokenFile = config.age.secrets.k3s-token.path;
    # Keep flannel VXLAN, CoreDNS and local-path at their k3s defaults.
    extraKubeletConfig = {
      # Agent hosts retain zram for interactive work; pods keep memory limits
      # and do not use swap themselves.
      failSwapOn = false;
      memorySwap.swapBehavior = "NoSwap";
      kubeReserved = {
        cpu = "250m";
        memory = "512Mi";
      };
      evictionHard = {
        "memory.available" = "500Mi";
        "nodefs.available" = "10%";
        "imagefs.available" = "15%";
        "nodefs.inodesFree" = "5%";
      };
    };
  };

  # NetworkManager must not manage the interfaces created by flannel/CNI.
  networking.networkmanager.unmanaged = ["interface-name:flannel*" "interface-name:cni*" "interface-name:veth*"];
  networking.firewall = {
    allowedTCPPorts = [10250 31200]; # kubelet and RSSHub NodePort
    allowedUDPPorts = [8472]; # flannel VXLAN, trusted LAN only
    trustedInterfaces = ["cni0" "flannel.1"];
  };
}
