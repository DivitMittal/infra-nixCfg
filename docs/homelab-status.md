# Homelab rollout status

Last checked: 2026-11-18. Branch: `feat/adding-t640`, public PR #37.

| Machine | Intended role                               | Current verified state (2026-11-19)                                                                                                |
| ------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| T1      | NixOS host and ImmortalWrt VM router        | Router VM up, DHCP/DNS/internet working; latest system with console passwords is the boot default                                  |
| T2      | Sway desktop, API-backed agents, k3s worker | k3s node Ready; greetd, console passwords and persistent NetworkManager profile deployed; full Home Manager profile still building |
| T3      | k3s server and services                     | Back online at 192.168.2.106 on generation 3: persistent profile, NIC watchdog, console passwords; k3s Ready, RSSHub/Redis healthy |
| MON1    | Prometheus, Grafana and network probes      | Healthy at 192.168.2.5; scrapes all four node exporters (up=1)                                                                     |
| S1      | TP-Link TL-SG105E managed LAN switch        | Management at 192.168.2.2; all five ports linked                                                                                   |

L1 uses a static 192.168.2.4 address on Ethernet (`en23`) with no gateway.
Its internet route stays on Wi-Fi, so router maintenance does not interrupt the
management session. The Ethernet link currently negotiates gigabit.

## Deployment details

- T2 and MON1 have the system configuration from commit `6535267e` activated
  and installed as their boot default. On MON1, replacing the imported DHCP
  lease with its real NetworkManager profile removed the duplicate default route.
- With mutable users, the pinned NixOS activation code preserves existing locked
  shadow entries. Their declared hashes were applied from decrypted files to
  enable console login. Commit `49825895` makes this declarative through
  `users.mutableUsers = false`; its new systems still need building/deploying.
- Commit `9516d724` provisions persistent wired NetworkManager profiles for T2,
  T3 and MON1. It is awaiting CI and deployment. T1 uses its own networkd setup.
- SSH remains key-only. Console credentials use the encrypted `users/div.age`
  and `users/root.age` hashes, shared with the existing VPS configuration.
- The complete T2 Home Manager build is blocked by an aicommit2 pnpm dependency
  fetch failure; other packages are still building under `--keep-going`.
  Do not report the graphical session or agent tools as complete until profile
  activation and runtime checks pass.
- T3's last successful service checks had both k3s nodes Ready and RSSHub/Redis
  healthy. These checks are historical: the single-server cluster cannot be
  considered healthy while T3 is unreachable. A local-subnet ARP scan did not
  find its recorded NIC, although all switch ports currently have link.

## Resume commands

SSH keys: NixOS hosts use `~/.ssh/agenix/id_ed25519`; the ImmortalWrt guest
uses `~/.ssh/github/id_ed25519`. Verify any changed host key before accepting it.

Runtime build units on T2:

- `hm-resume`: full `homeConfigurations.T2.activationPackage`; logs in
  `/var/log/hm-resume.log`, output in `/var/log/hm-resume.out`.
- `host-updates-build`: builds the committed system configurations sequentially;
  logs and output in `/var/log/host-updates.log` and `.out`.

Inspect `ActiveState`, `SubState`, `Result` and the actual output file. An active
unit with `RemainAfterExit=yes` may have completed; `Result=success` alone on a
running or absent transient unit is not proof that a build succeeded.

The guarded activation helper used a separate systemd rollback timer so an SSH
loss would not prevent rollback. Cancel the timer only after external network
and service checks, then install the validated system as the boot default.

## Remaining requested work

1. Restore access to T3, diagnose its actual network state from the console or
   previous-boot logs, and deploy a persistent wired profile. Avoid inferring
   power state or firmware failure solely from missing ARP/SSH responses.
2. Finish T2's complete Home Manager profile, activate it as `div`, and verify
   Sway plus agent tools. Deploy T3's tty/agent profile when its network is back.
3. Deploy the immutable-account and persistent-profile fixes to the fleet and
   verify console login configuration, DHCP, cluster readiness, workloads and
   MON1's real probe results (`probe_success`, not just scrape `up`).
4. Review/merge PR #37 after runtime checks and CI; close absorbed #60 and #67.
   Private secrets PRs #71, #72 and #73 are merged; the input tracks master.
5. Integrate heavier observability from #36; assess external NAS/backup disks
   with the owner before formatting any of them. No external disk erase is approved.
6. Verify ISP DMZ forwarding to 192.168.1.254 and configure the USB Wi-Fi AP
   if retained in the final network design.
7. Continue vendor BIOS work using the verified limitations in
   [the BIOS findings](hp-t640-bios.md). Firmware flashing and vendor-setting
   tests require explicit approval; the standard boot-order module defaults to
   checking only. A previous unexplained link loss is not proof of a BIOS hang.
8. Decide the macOS build-offload approach. No macOS VM has been configured.

The [k3s architecture](homelab-k3s.md) uses T3 as the only server and Redis
storage node, with T2 as a worker. It is not HA. T1 and MON1 stay outside it.

## 2026-11-19 T3 outage: loose cable

T3's installed boots never got carrier (`Link is Down` only), and its firmware
PXE sent nothing either. The rescue installer got a link once T3 was moved to
another switch port, and T2 then lost its link on T3's old port. The cause was
a loose cable on that port. After it was reseated, T3 was reinstalled from the
rescue installer with its latest system (generation 3) and booted normally.
