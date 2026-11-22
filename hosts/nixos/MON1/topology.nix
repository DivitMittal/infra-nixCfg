_: {
  topology.self = {
    hardware.info = "Lenovo S100 (Intel Atom, 2 GiB RAM) - monitoring node: Prometheus :9090, Grafana :3000, blackbox probes. Formerly the OpenWrt router R1 (hosts/openwrt/R1 kept for rollback)";
    interfaces.lan0 = {
      network = "home";
      type = "ethernet";
    };
    services = {
      prometheus = {
        name = "Prometheus";
        info = "http://MON1:9090";
      };
      grafana = {
        name = "Grafana";
        info = "http://MON1:3000";
      };
    };
  };
}
