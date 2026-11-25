_: let
  # Matches the T3 DHCP reservation in network.nix.
  t3 = "192.168.2.8";
  forward = name: proto: externalPort: internalPort: {
    _type = "redirect";
    inherit name proto;
    family = "ipv4";
    src = "wan";
    src_dport = externalPort;
    dest = "lan";
    dest_ip = t3;
    dest_port = internalPort;
    target = "DNAT";
    reflection = "0";
  };
in {
  # Never forward admin sshd or the Kubo HTTP gateway/API.
  uci.settings.firewall = {
    qezta_ssh = forward "Qezta SSH portfolio" ["tcp"] "22" "30022";
    qezta_ipfs_swarm = forward "Qezta IPFS swarm" ["tcp" "udp"] "4001" "4001";
  };
}
