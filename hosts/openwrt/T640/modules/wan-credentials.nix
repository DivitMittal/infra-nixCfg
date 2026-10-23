_: {
  # Real per-line PPPoE username+password are a real external secret (not
  # one we can generate), so they never land in git or the declarative UCI
  # JSON (which only ever contains the CHANGEME placeholders from
  # network.nix). flake/openwrt-t640.nix's `set_wan_credentials` decrypts
  # them from infra-nixCfg-secrets at deploy time and writes each line's
  # "username\npassword" into a root-only file over SSH — this hook then
  # reads those files and applies them to live UCI. Same pattern as R1's
  # wifi-backup PSK (hosts/openwrt/R1/modules/wifi-backup.nix).
  uci.files = [
    {
      path = "/etc/nuci/reconcile.d/60-wan-credentials";
      executable = true;
      content = ''
        #!/bin/sh
        set -eu

        changed=0

        for line in 1 2; do
          cred_file="/etc/nuci/wan''${line}-credentials"
          [ -s "$cred_file" ] || {
            echo "PPPoE line $line credentials are missing at $cred_file; deploy did not inject them" >&2
            exit 1
          }

          username="$(sed -n '1p' "$cred_file")"
          password="$(sed -n '2p' "$cred_file")"

          current_username="$(uci -q get network.wan''${line}.username || true)"
          current_password="$(uci -q get network.wan''${line}.password || true)"

          if [ "$current_username" != "$username" ] || [ "$current_password" != "$password" ]; then
            uci set network.wan''${line}.username="$username"
            uci set network.wan''${line}.password="$password"
            changed=1
          fi
        done

        if [ "$changed" -eq 1 ]; then
          uci commit network
          /etc/init.d/network reload
        fi
      '';
    }
  ];
}
