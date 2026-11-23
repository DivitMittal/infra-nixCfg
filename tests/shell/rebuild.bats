#!/usr/bin/env bats
# utils/home_rebuild.sh (hms) and utils/hosts_rebuild.sh (hts)

setup() {
  load helpers
  setup_sandbox
  init_repo
  cd "$REPO"
}

## ── home_rebuild.sh ─────────────────────────────────────────────────────────

@test "hms fails with guidance when home-manager is missing" {
  run bash "$UTILS/home_rebuild.sh"
  [ "$status" -eq 1 ]
  assert_output_contains "home-manager not found."
  assert_output_contains "bootstrap.sh home"
}

@test "hms switches the current host and forwards flags" {
  stub home-manager
  run bash "$UTILS/home_rebuild.sh" -v --show-trace
  [ "$status" -eq 0 ]
  assert_logged "home-manager -v --show-trace --keep-going --flake .#testhost switch"
}

@test "hms tags a successful clean rebuild with the home prefix" {
  stub home-manager
  run bash "$UTILS/home_rebuild.sh"
  [[ "$(tags)" =~ ^home-buildable- ]]
}

@test "hms does not tag a failed rebuild" {
  stub home-manager 'exit 3'
  run bash "$UTILS/home_rebuild.sh"
  [ -z "$(tags)" ]
}

@test "hms propagates the home-manager exit status" {
  stub home-manager 'exit 3'
  run bash "$UTILS/home_rebuild.sh"
  [ "$status" -eq 3 ]
}

## ── hosts_rebuild.sh ────────────────────────────────────────────────────────

@test "hts on Darwin fails with guidance when darwin-rebuild is missing" {
  stub uname 'echo Darwin'
  run bash "$UTILS/hosts_rebuild.sh"
  [ "$status" -eq 1 ]
  assert_output_contains "darwin-rebuild not found."
}

@test "hts on Darwin runs darwin-rebuild via sudo" {
  stub uname 'echo Darwin'
  stub_sudo
  stub darwin-rebuild
  run bash "$UTILS/hosts_rebuild.sh" --show-trace
  [ "$status" -eq 0 ]
  assert_output_contains "(DARWIN)"
  assert_logged "sudo darwin-rebuild --show-trace --keep-going --flake .#testhost switch"
  [[ "$(tags)" =~ ^host-buildable- ]]
}

@test "hts on Darwin prefers darwin-rebuild over other tools on PATH" {
  stub uname 'echo Darwin'
  stub_sudo
  stub darwin-rebuild
  stub nixos-rebuild
  stub nix-on-droid
  run bash "$UTILS/hosts_rebuild.sh"
  refute_logged "nixos-rebuild"
  refute_logged "nix-on-droid"
}

@test "hts on Linux runs nix-on-droid without sudo when available" {
  stub uname 'echo Linux'
  stub_sudo
  stub nix-on-droid
  stub nixos-rebuild
  run bash "$UTILS/hosts_rebuild.sh"
  [ "$status" -eq 0 ]
  assert_output_contains "(DROID)"
  assert_logged "nix-on-droid --keep-going --flake .#testhost switch"
  refute_logged "sudo"
  refute_logged "nixos-rebuild"
}

@test "hts on Linux runs nixos-rebuild via sudo" {
  stub uname 'echo Linux'
  stub_sudo
  stub nixos-rebuild
  run bash "$UTILS/hosts_rebuild.sh"
  [ "$status" -eq 0 ]
  assert_output_contains "(NIXOS)"
  assert_logged "sudo nixos-rebuild --keep-going --flake .#testhost switch"
}

@test "hts fails with guidance when no rebuild tool exists" {
  stub uname 'echo Linux'
  run bash "$UTILS/hosts_rebuild.sh"
  [ "$status" -eq 1 ]
  assert_output_contains "No rebuild tool found"
}

@test "hts does not tag a failed rebuild" {
  stub uname 'echo Linux'
  stub_sudo
  stub nixos-rebuild 'exit 4'
  run bash "$UTILS/hosts_rebuild.sh"
  [ -z "$(tags)" ]
}

@test "hts propagates the rebuild exit status" {
  stub uname 'echo Linux'
  stub_sudo
  stub nixos-rebuild 'exit 4'
  run bash "$UTILS/hosts_rebuild.sh"
  [ "$status" -eq 4 ]
}
