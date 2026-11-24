# T3 — HP t640, Ryzen R1505G (2 cores / 4 threads), 16 GiB RAM, 256 GB NVMe
# (live inventory 2026-11-22): home-lab services, plus overflow capacity for
# API-backed AI agents (host tuning in hosts/nixos/_homelab/agents.nix; agent
# CLIs from ai-nixCfg via the tty+dev home-manager profile).
#
# Add each service as its own file in this directory (import-tree picks it
# up), as k3s manifests where appropriate. T3 is the single SQLite-backed k3s
# server; T2 is its worker. Planned here as well: the
# heavier observability pieces (Loki/Tempo from PR #36) once MON1's light
# stack is running.
_: {}
