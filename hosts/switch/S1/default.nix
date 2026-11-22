# Ports, measured from S1's per-port counters on 2026-11-19 (see also
# flake/topology.nix):
#   1 T3 · 2 T1 (router VM lan0) · 3 MON1 (100 Mbit/s NIC) · 4 T2 · 5 S2 uplink
_: {
  terraform.required_providers.tplinkeasysmart = {
    source = "lucavb/tplink-easysmart";
    version = "~> 0.3";
  };

  variable.switch_s1_password = {
    type = "string";
    sensitive = true;
    description = "Admin password for S1's Easy Smart web UI (infra-nixCfg-secrets: secrets/network/S1.age)";
  };

  provider.tplinkeasysmart = {
    # TP-Link TL-SG105E v5: static management address, also reserved by the
    # router so DHCP cannot allocate it to another device. Easy Smart switches
    # only speak HTTP, so the password crosses the LAN in the clear; another
    # reason the ISP side never touches this switch.
    host = "192.168.2.2";
    username = "admin";
    password = "\${var.switch_s1_password}";
    insecure_http = true;
  };

  data.tplinkeasysmart_system_info.S1 = {};

  # One flat, untagged LAN. WAN has its own NIC on T1, cabled straight to the
  # GN XPON, so nothing is trunked here. Re-enable 802.1Q only for real
  # segmentation (e.g. an IoT VLAN), which can only reach devices on S1's own
  # ports: S2 is unmanaged, so everything behind port 5 shares one VLAN.
  resource.tplinkeasysmart_vlan_8021q_mode.flat = {
    enabled = false;
  };

  # Keeps multicast (mDNS, SSDP) from flooding every port.
  resource.tplinkeasysmart_igmp_snooping.S1 = {
    enabled = true;
    report_message_suppression = false;
  };

  # S2 is unmanaged, and it had port isolation switched on until 2026-11-19.
  # Cap broadcast/multicast arriving from it so a loop or misbehaving device
  # behind it can't flood the home-lab ports. 64 Mbit/s is far above normal
  # discovery traffic.
  resource.tplinkeasysmart_port_storm_control.port5 = {
    port_id = 5;
    enabled = true;
    rate_kbps = 65536;
    storm_types = ["broadcast" "multicast"];
  };

  # Adopt the live singletons instead of recreating them.
  import = [
    {
      to = "tplinkeasysmart_igmp_snooping.S1";
      id = "igmp_snooping";
    }
    {
      to = "tplinkeasysmart_port_storm_control.port5";
      id = "5";
    }
  ];

  # Not managed here; set by hand in the web UI and must be re-done after a
  # factory reset:
  #   - Loop Prevention: enabled (System > Loop Prevention). The provider has
  #     no resource for it.
  #   - Port settings: every port enabled, speed auto, flow control off (pause
  #     frames would stall a port for one slow receiver, e.g. MON1's
  #     100 Mbit/s NIC). The provider can't import port settings, and
  #     re-writing them can renegotiate links (port 2 is the router).
  # The QoS mode is left unmanaged: no QoS is configured and there is no
  # bufferbloat to fix (~5 ms loaded latency on the 400 Mbit/s line).
}
