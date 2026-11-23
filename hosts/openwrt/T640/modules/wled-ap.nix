# Keep LAN -> WLED API/MQTT traffic bidirectional without double NAT.
# T1 forwards the dedicated AP subnet through its existing LAN attachment.
_: {
  uci.settings.network.wled_ap = {
    _type = "route";
    interface = "lan";
    target = "192.168.50.0";
    netmask = "255.255.255.0";
    gateway = "192.168.2.3";
  };
}
