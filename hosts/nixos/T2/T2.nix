# T2 — the highest-spec t640: Linux GUI box and the main agent runner.
# "AI" here means API-backed agents (Claude Code, Codex, ...) that need spare
# cores and RAM, not local inference; host tuning for that is in
# hosts/nixos/_homelab/agents.nix, the agent CLIs come from ai-nixCfg via the
# full home-manager profile (home/default.nix). The Sway session comes from
# the shared desktop layer (common/hosts/nixos/desktop.nix lists T2).
_: {
  # Vega 3 iGPU, for the Sway session.
  hardware.graphics.enable = true;
}
