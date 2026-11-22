{lib, ...}: let
  # Stale sections from R1's earlier configs. rawUci can't express "delete if
  # it exists" (its lines run under `set -e` and may not contain shell
  # metacharacters), so this is a reconcile.d hook instead.
  staleSections = [
    "firewall.lan_zone"
    "firewall.wan_zone"
    "firewall.lan"
    "firewall.wan"
    "network.wan_vlan"
    "network.wan_mobile"
    "network.usb_reverse"
    "dhcp.usb_reverse"
    "mwan3.wan"
    "mwan3.wan_mobile"
    "mwan3.wan_m1"
    "mwan3.wan_mobile_m2"
    "mwan3.failover"
    "mwan3.default_rule"
    "sqm.wan"
  ];
in {
  uci.files = [
    {
      path = "/etc/nuci/reconcile.d/10-cleanup";
      executable = true;
      content = ''
        #!/bin/sh
        set -eu
        changed=""
        for section in ${lib.concatStringsSep " " staleSections}; do
          if uci -q get "$section" >/dev/null; then
            uci delete "$section"
            changed="$changed ''${section%%.*}"
          fi
        done
        for config in $(echo "$changed" | tr ' ' '\n' | sort -u); do
          uci commit "$config"
        done
      '';
    }
  ];
}
