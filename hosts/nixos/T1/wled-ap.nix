# Wi-Fi carries WLED control/API traffic; HyperHDR stays on USB Adalight.
{
  config,
  inputs,
  ...
}: let
  iface = "wled0";
  deviceUnit = "sys-subsystem-net-devices-${iface}.device";
in {
  age.secrets.t1-wled-ap = {
    file = inputs.infra-nixCfg-secrets + "/secrets/homelab/t1-wled-ap.age";
    mode = "0400";
  };

  # USB-port-derived interface names change when the adapter is moved.
  # This is T1's only adapter using this driver; no private MAC is needed.
  systemd.network.links."15-wled-ap" = {
    matchConfig.Driver = "rtw88_8821cu";
    linkConfig.Name = iface;
  };
  networking.networkmanager.unmanaged = ["interface-name:${iface}"];
  networking.interfaces.${iface}.useDHCP = false;
  systemd.network.networks."30-wled-ap" = {
    matchConfig.Name = iface;
    address = ["192.168.50.1/24"];
    networkConfig = {
      ConfigureWithoutCarrier = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  services.hostapd = {
    enable = true;
    radios.${iface} = {
      band = "2g";
      channel = 6;
      # Keep the verified 20 MHz channel width for the ESP32.
      wifi4.capabilities = [];
      networks.${iface} = {
        ssid = "T1-WLED";
        authentication = {
          # Match the WPA2-PSK/CCMP mode verified by the runtime AP trial.
          mode = "wpa2-sha1";
          wpaPasswordFile = config.age.secrets.t1-wled-ap.path; # ggignore: runtime path, not a password
        };
        settings.ieee80211w = 0;
      };
    };
  };
  # The USB adapter can disappear and return without rebooting the host.
  systemd.services.hostapd.wantedBy = [deviceUnit];

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      interface = iface;
      bind-dynamic = true;
      port = 0;
      dhcp-range = ["192.168.50.20,192.168.50.99,255.255.255.0,12h"];
      dhcp-option = [
        "option:router,192.168.50.1"
        "option:dns-server,192.168.2.1"
      ];
    };
  };
  networking.firewall.interfaces.${iface}.allowedUDPPorts = [67];
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
}
