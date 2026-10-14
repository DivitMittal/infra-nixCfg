## blackbox_exporter module definitions consumed by `services.prometheus.exporters.blackbox`.
##
## Modules:
##   - icmp        : raw ping (used for fleet mesh latency matrix)
##   - tcp_connect : connect-and-close (port liveness)
##   - https_2xx   : HTTPS GET, accepts 2xx; verifies cert chain → exposes cert expiry
##   - dns_a       : DNS A-record resolution check
{pkgs}:
pkgs.writeText "blackbox.yaml" (builtins.toJSON {
  modules = {
    icmp = {
      prober = "icmp";
      timeout = "5s";
      icmp = {
        preferred_ip_protocol = "ip4";
        ip_protocol_fallback = true;
      };
    };
    tcp_connect = {
      prober = "tcp";
      timeout = "5s";
    };
    https_2xx = {
      prober = "http";
      timeout = "10s";
      http = {
        valid_status_codes = [];
        method = "GET";
        fail_if_ssl = false;
        fail_if_not_ssl = true;
        preferred_ip_protocol = "ip4";
      };
    };
    dns_a = {
      prober = "dns";
      timeout = "5s";
      dns = {
        query_name = "example.com";
        query_type = "A";
        valid_rcodes = ["NOERROR"];
        preferred_ip_protocol = "ip4";
      };
    };
  };
})
