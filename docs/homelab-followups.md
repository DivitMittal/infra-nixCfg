# Homelab follow-up coordination

Started 2026-11-20 after the base fleet rollout (#85, #87, #89). The user
requested nine follow-ups. Keep findings and deployment evidence in the scoped
documents below; do not infer success from a branch or green evaluation alone.

| Workstream              | Scope and durable record                                             | State                                                                                                                                                                                                                           |
| ----------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SNMP / L1 Ethernet      | R0 SNMP polling on MON1 and client tools on L1; docs/homelab-snmp.md | Worker investigating. L1 en23 currently negotiates 100baseTX/full.                                                                                                                                                              |
| DASH / BIOS             | docs/homelab-dash.md and docs/hp-t640-bios.md                        | Worker investigating Linux provisioning and a reproducible BIOS backend; no live firmware mutation authorized.                                                                                                                  |
| HDDs                    | docs/homelab-storage.md                                              | Worker inventorying disks and implementing safe opt-in declarative storage; no disk formatting authorized.                                                                                                                      |
| Tailscale / build cache | docs/homelab-build-cache.md                                          | Worker reviewing #75, existing Attic, GitHub Actions Darwin builds and credential needs. No L1 activation or broad dependency refresh.                                                                                          |
| MON1 display            | hosts/nixos/MON1/console.nix                                         | Built-in LVDS panel connected, lid open, tty1/agetty healthy; fb0 blank=4. Writing blank=0 restored an unblanked framebuffer; tty1 contains the login prompt. Physical confirmation pending. Boot-time reconciliation prepared. |
| Redis                   | hosts/nixos/T3/rsshub.nix and docs/homelab-k3s.md                    | Replacing RSSHub's cache with memory (256 entries). Manifest server dry-run passed; rollout pending. Retain old PVC/PV.                                                                                                         |

## Coordination rules

- Workers use distinct worktrees and branches. The parent reviews and integrates;
  workers must not independently deploy or merge conflicting host changes.
- Full configuration evaluation and flake checks run on GitHub Actions. Target
  deployment builds run on T2 with bounded concurrency, coordinated by the parent.
- Preserve router availability. Do not reboot, flash, change vendor BIOS settings,
  load experimental firmware drivers, or erase external storage as investigation.
- Store credentials encrypted in infra-nixCfg-secrets. Never put plaintext secrets
  in git, Nix expressions/store paths, command arguments or chat output.
- When credentials are required, use the user-authorized macOS dialog to direct
  them to the official provider website and a secure local submission mechanism.
- L1's current default route is through 192.168.2.1 on en23. Earlier statements
  that Wi-Fi still provides its default route are historical, not current evidence.
