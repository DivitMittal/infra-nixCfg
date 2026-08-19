_: let
  deleteIfExists = section: "uci -q get ${section} >/dev/null 2>&1 && uci delete ${section} || true";
in {
  uci.rawUci = [
    (deleteIfExists "firewall.lan_zone")
    (deleteIfExists "firewall.wan_zone")
    (deleteIfExists "firewall.lan")
    (deleteIfExists "firewall.wan")
    (deleteIfExists "network.wan_vlan")
    (deleteIfExists "network.wan_mobile")
    (deleteIfExists "network.usb_reverse")
    (deleteIfExists "dhcp.usb_reverse")
    (deleteIfExists "mwan3.wan")
    (deleteIfExists "mwan3.wan_mobile")
    (deleteIfExists "mwan3.wan_m1")
    (deleteIfExists "mwan3.wan_mobile_m2")
    (deleteIfExists "mwan3.failover")
    (deleteIfExists "mwan3.default_rule")
    (deleteIfExists "sqm.wan")
    "uci commit firewall"
    "uci commit network"
    "uci commit dhcp"
    "uci commit mwan3"
    "uci commit sqm"
  ];
}
