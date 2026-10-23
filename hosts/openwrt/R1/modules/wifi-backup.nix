{
  wanMode,
  lib,
  ...
}: let
  isWifiBackup = wanMode == "wifi-backup";
in {
  # R1's onboard RTL8188EU (0bda:8179) binds cleanly to rtl8xxxu and loads
  # firmware, but `iw list` only advertises managed/monitor modes — no AP —
  # so it can't host a recovery AP. Repurposed as a Wi-Fi *station* instead:
  # a backup WAN path that associates to R0's own Wi-Fi (SSID
  # Airtel_anku_8585) when wanMode = "wifi-backup", as an alternative to the
  # normal wan0 Ethernet uplink or the android-tether USB path.
  uci = {
    packages = [
      "kmod-rtl8xxxu"
      "rtl8188eu-firmware"
      "kmod-mac80211"
      "kmod-cfg80211"
      "iw"
      "wireless-regdb"
      "wpad-basic-mbedtls"
    ];

    settings = lib.mkIf isWifiBackup {
      wireless = {
        radio0 = {
          _type = "wifi-device";
          type = "mac80211";
          # Stable USB topology path (onboard port), not the PHY index,
          # which can shift across reboots/enumeration order.
          path = "pci0000:00/0000:00:1d.7/usb3/3-6/3-6.2/3-6.2:1.0";
          band = "2g";
          channel = "1";
          htmode = "HT20";
          disabled = "0";
        };

        # No `key` here on purpose: the WPA2 PSK for R0's network is a real
        # secret (not one we can generate), so it never lands in git or the
        # Nix store. It's injected into live UCI by the
        # /etc/nuci/reconcile.d/65-wifi-psk hook below, from a root-only
        # file the deploy flow writes over SSH (see flake/openwrt.nix).
        wan_sta = {
          _type = "wifi-iface";
          device = "radio0";
          mode = "sta";
          network = "wan";
          ssid = "Airtel_anku_8585";
          encryption = "psk2";
        };
      };
    };

    files = lib.mkIf isWifiBackup [
      {
        path = "/etc/nuci/reconcile.d/65-wifi-psk";
        executable = true;
        content = ''
          #!/bin/sh
          set -eu

          psk_file=/etc/nuci/wifi-psk
          [ -s "$psk_file" ] || {
            echo "Wi-Fi backup WAN is enabled but $psk_file is missing; deploy did not inject the R0 PSK" >&2
            exit 1
          }
          psk="$(cat "$psk_file")"

          current="$(uci -q get wireless.wan_sta.key || true)"
          [ "$current" = "$psk" ] && exit 0

          uci set wireless.wan_sta.key="$psk"
          uci commit wireless
          wifi reload
        '';
      }
    ];
  };
}
