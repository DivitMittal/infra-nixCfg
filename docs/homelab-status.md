# Homelab rollout status

Last verified: 2026-11-18. Configurations are on `feat/adding-t640` / PR #37.

| Machine                  | Intended role                            | Deployment state                                                           |
| ------------------------ | ---------------------------------------- | -------------------------------------------------------------------------- |
| T1, lowest-spec HP t640  | NixOS host, ImmortalWrt VM router        | Installed; VM reboot, DHCP, DNS and outbound internet verified             |
| T2, highest-spec HP t640 | GUI, API-backed AI agents, k3s worker    | Configuration prepared; hardware capture and installation pending          |
| T3, medium-spec HP t640  | k3s server, services, overflow AI agents | Installed; k3s Ready; RSSHub/Redis healthy; Redis persistence verified     |
| MON1, Lenovo S100        | External monitoring, possible light NAS  | OpenWrt at 192.168.2.5; DHCP/RA off; NixOS monitoring installation pending |
| S1, TP-Link TL-SG105E v5 | Flat managed LAN switch                  | Management restored to 192.168.2.2; Terraform plan reports no changes      |

L1 uses DHCP on its Ethernet adapter through S1, with reservation
192.168.2.4 and gateway 192.168.2.1. Wi-Fi remains available. Its VPN/proxy
installs more-specific routes, so the default-route display alone does not
prove that every L1 internet connection uses Ethernet. Ethernet negotiated
100 Mbit/s at verification; inspect the cable/adapter/port to restore gigabit.

## Outstanding work requested in the conversation

- Merge private secrets PR #72 before public PR #37, then return the public
  flake's temporary secrets-branch reference to `master`.
- Bootstrap T2, join its k3s worker, and deploy the T2/T3 AI Home Manager profiles.
- Bootstrap MON1, deploy Prometheus/Grafana/probes, and verify network coverage.
- Add the heavier observability services from PR #36 to the k3s services
  host, with resource and storage sizing.
- Assess the S100's disks, USB performance and memory before adding NAS.
- Configure the planned router USB Wi-Fi AP, if still desired; Wi-Fi currently
  remains on the ISP ONT/router.
- Verify incoming forwarding after setting the ISP router's DMZ target to
  192.168.1.254. Outbound routing is already verified.
- Investigate a working HP firmware-settings backend. The inventory and
  [findings](hp-t640-bios.md) are implemented; enforcement remains unavailable
  on the observed malformed `hp-bioscfg` interfaces. T3's AMD-V is disabled,
  which blocks KVM guests but does not block k3s containers.
- Decide whether to implement the requested macOS builder VM or use CI builds.
  No macOS VM has been configured.
- Complete CI validation and PR #37 review/merge, close the absorbed #60/#67,
  and triage the remaining unrelated PR backlog.

The current [k3s plan](homelab-k3s.md) supersedes the earlier decision to use
only native NixOS services. T1 remains outside Kubernetes. T3's single-server
datastore and local Redis volume do not provide high availability.

## Completed rollout checks

T3 installation was approved and completed. RSSHub is reachable at
http://T3.lan:31200 (currently http://192.168.2.106:31200). A real GitHub
feed and Redis persistence across pod replacement were verified.

Connecting the old R1 OpenWrt installation introduced a second 192.168.2.1
and DHCP server. Its identity was verified through an isolated management
namespace before changing it. MON1 now uses 192.168.2.5 with gateway/DNS
192.168.2.1, DHCP disabled and IPv6 router advertisements disabled. Its previous
network/DHCP/system configurations are backed up locally under
`/root/before-mon1-management-change/`. No MON1 disk was erased or OS replaced.

The temporary management namespace was on T3's installer and disappeared on
reboot. T1 remained the router. T3's normal post-boot gateway is dynamic again.
