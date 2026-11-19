# Homelab rollout status

Last checked: 2026-11-20. PR #37 and #87 are merged; profile/deployment follow-up is #85.

| Machine | Intended role                          | Verified state                                                                                                             |
| ------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| T1      | NixOS host and ImmortalWrt VM router   | Router reachable at 192.168.2.1; static WAN 192.168.1.254 is up behind the ISP router                                      |
| T2      | Sway desktop, agent tools, k3s worker  | Reachable at 192.168.2.171; k3s Ready; greetd active; complete Home Manager profile activated                              |
| T3      | k3s server, services and Attic cache   | Reachable at 192.168.2.8; k3s Ready; RSSHub, Redis and SSH portfolio pods Running; terminal Home Manager profile activated |
| MON1    | Prometheus, Grafana and network probes | Reachable at 192.168.2.5; no failed systemd units on the latest check                                                      |
| S1      | TP-Link TL-SG105E managed LAN switch   | Management address 192.168.2.2                                                                                             |

L1 uses static 192.168.2.4/24 on Ethernet with no gateway; Wi-Fi supplies its
internet route. No L1 system or Home Manager activation is part of this rollout.

## Completed profile repairs

PR #85 repairs REAPER extraction and Linux libraries, LeetCode's bundled
Oniguruma compiler mode, four legacy Raycast CLI downloads, stock-tracker's
unused Electron download, and the Mullvad CLI/GUI collision. All selected
applications and 23 launcher extensions are retained.

Herdr is explicitly available during activation so its plugin hook cannot
prematurely exit before user service reloads. Codex uses an explicit Bunx
`@latest` tag to resolve correctly on fresh compute-node caches.

Both final Home Manager builds completed, and activation succeeded as `div`:

- T2: `/nix/store/dz5js6xwx78xw8j8p3cig31vk6k2l190-home-manager-generation`
- T3: `/nix/store/wca9bv0f92wciivc6pm6pi72mvca5hs8-home-manager-generation`

Normal user login environments on both hosts ran Codex 0.170.0, Claude Code
2.1.316 and Herdr 0.7.1 successfully. T2's Sway configuration passed validation
in the previous session; physical display login remains unconfirmed. SSH stays
key-only; console passwords come from encrypted user secrets, not this document.

## Deployment follow-up

PR #86 added the SSH portfolio. PR #87 fixes its writable host-key directory,
updates its renderer and makes deploy-rs use GNU sed explicitly. The previous
uutils sed error happened after switching and prevented a clean rollback.

T3's running system and saved profile now both point to
`/nix/store/4m0wk25x1hnavdxdvq6vb0nvfvq2ik2m-nixos-system-T3-26.11.20260705.c4013e5`.
The integrated system was tested with an independent five-minute rollback timer.
SSH, k3s readiness, workloads, RSSHub and Attic passed before saving it as the
boot default and cancelling the timer. No reboot was performed.

T2's DHCP reservation was applied from the pinned private inventory using a
scoped UCI update and dnsmasq reload. A root-only-directory backup of the prior
DHCP configuration is on the router; no WAN or firewall changes were applied.

Obsolete failed build/test unit states on T2 were cleared after their replacement
builds and complete profile activations succeeded. No failed systemd units
remained on T1, T2, T3 or MON1 at the final check.

MON1 returned `up=1` for all four node exporters and `probe_success=1` for all
seven configured probes. RSSHub returned a valid feed with 13 items through
T2's NodePort; T3's Attic cache-info endpoint responded successfully.

## Operations and evidence

NixOS SSH identity: `~/.ssh/agenix/id_ed25519`. Router identity:
`~/.ssh/github/id_ed25519`. Verify host keys before accepting changes.

Latest profile activation logs:

- T2: `/var/log/t2-home-verified.log`
- T3: `/var/log/t3-home-verified.log`

Integrated T3 build on T2: `homelab-integrated-build-20261120.service`, logs
`/var/log/homelab-integrated-build.log`, output `.out`. An active unit using
`RemainAfterExit=yes` can be finished: check `SubState`, `ExecMainStatus` and
output together. `Result=success` on a running or absent unit is insufficient.

Heavy flake evaluation and flake checks run on GitHub Actions. Deployment builds
run on T2; do not perform full configuration evaluation or deployment on L1.

## Remaining requested work

1. Finish #85 review and CI after integrating current master; merge once green.
2. Review dedicated WLED AP #83 and Tailscale #75 separately; do not assume
   either is deployed merely because a branch exists.
3. Integrate additional observability from #36 and design external NAS/backup
   storage. No external-disk formatting is approved.
4. Continue vendor BIOS investigation using [verified findings](hp-t640-bios.md).
   Firmware flashes and vendor-setting experiments require explicit approval.
   DASH is enabled in firmware but authenticated management remains unverified;
   see [DASH status](homelab-dash.md).
5. Decide macOS build offload. No macOS VM is configured; #64 is not evidence
   that such a VM exists. Dependency refresh/L1 work in #84 is a separate task.

The [k3s architecture](homelab-k3s.md) uses T3 as its only server and Redis
storage node, with T2 as a worker. It is not HA. T1 and MON1 remain outside it.

The earlier T3 outage was traced to a loose cable. Missing ARP or SSH alone
must not be interpreted as power-off or a firmware failure.
