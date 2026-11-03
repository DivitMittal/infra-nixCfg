## Exposes the resolved blackbox target lists for templating elsewhere
## (currently only by the network-mesh dashboard generator).
{cfg}: {
  icmp = map (h: h.address) cfg.fleet.hosts;
  tcp = map (t: "${t.address}:${toString t.port}") cfg.blackbox.tcpTargets;
  https = cfg.blackbox.httpsCertTargets;
  dns = cfg.blackbox.dnsTargets;
}
