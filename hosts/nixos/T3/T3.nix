# T3 — the medium-spec t640: home-lab services, plus overflow capacity for
# API-backed AI agents (host tuning in hosts/nixos/_homelab/agents.nix; agent
# CLIs from ai-nixCfg via the tty+dev home-manager profile).
#
# Add each service as its own file in this directory (import-tree picks it
# up), as a native NixOS module where one exists. Planned here as well: the
# heavier observability pieces (Loki/Tempo from PR #36) once MON1's light
# stack is running.
_: {}
