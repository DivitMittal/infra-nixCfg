_: {
  terraform.required_providers.tplinkeasysmart = {
    source = "lucavb/tplink-easysmart";
    version = "~> 0.3";
  };

  variable.switch_s1_password = {
    type = "string";
    sensitive = true;
    description = "Admin password for S1's Easy Smart web UI (OS-nixCfg-secrets: secrets/lan/S1.age; shared with R1)";
  };

  provider.tplinkeasysmart = {
    # TP-Link TL-SG105E; mgmt IP pinned via DHCP host record (see
    # hosts/openwrt/R1/modules/network.nix, dhcp.S1).
    host = "192.168.2.2";
    username = "admin";
    password = "\${var.switch_s1_password}";
    insecure_http = true;
  };

  data.tplinkeasysmart_system_info.S1 = {};

  # Disable the global 802.1Q mode rather than deleting VLAN/PVID resources one
  # at a time. On the TL-SG105E this atomically makes the stale WAN (VLAN10),
  # LAN (VLAN20), and their PVID assignments inactive, returning all ports to a
  # flat untagged network while preserving the switch password and management
  # settings. The resource's delete is intentionally a no-op, so removing it
  # later stops management without changing the live mode.
  resource.tplinkeasysmart_vlan_8021q_mode.flat = {
    enabled = false;
  };

  # S1 carries a single flat LAN now: WAN has its own dedicated NIC on R1
  # (wan0 → R0), so nothing is trunked here anymore. The old 802.1q VLAN20
  # existed only to split WAN+LAN over one router-on-a-stick cable; with that
  # gone, tagging is pure ceremony (R1 stripped VLAN20 straight back off), so
  # all five ports are left in one untagged broadcast domain. port1 is R1's
  # uplink (lan0); ports 2-5 are host-facing access ports. Re-introduce a VLAN
  # here only if you add real segmentation (e.g. a guest/IoT subnet).
  #
  # Beyond the global mode, no per-port resources are needed for a flat LAN.
  # Managed features worth enabling later (loop prevention, port mirroring)
  # depend on tplink-easysmart provider support; check
  # `terraform providers schema -json` before wiring them here.
}
