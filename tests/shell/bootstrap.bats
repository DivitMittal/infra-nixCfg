#!/usr/bin/env bats
# utils/bootstrap.sh

setup() {
  load helpers
  setup_sandbox
  init_repo
  cd "$REPO"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.ssh/agenix"
  touch "$HOME/.ssh/agenix/id_ed25519"

  # nix: --version prints, `flake metadata` honours $NIX_FLAKE_RC, `build` honours $NIX_BUILD_RC.
  stub nix 'case "$1" in
    --version) echo "nix (Nix) 2.99" ;;
    flake) exit "${NIX_FLAKE_RC:-0}" ;;
    build) exit "${NIX_BUILD_RC:-0}" ;;
  esac'
  stub_sudo
  stub uname 'echo Linux'
}

## ── pre-flight ──────────────────────────────────────────────────────────────

@test "refuses to run outside the repo root" {
  rm "$REPO/flake.nix"
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 1 ]
  assert_output_contains "No flake.nix in current directory"
}

@test "explains how to install nix when it is missing" {
  rm "$STUB_BIN/nix"
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 1 ]
  assert_output_contains "Nix is not installed."
  assert_output_contains "install.determinate.systems"
}

@test "stops when the flake does not evaluate" {
  export NIX_FLAKE_RC=1
  run bash "$UTILS/bootstrap.sh" home
  [ "$status" -eq 1 ]
  assert_output_contains "This flake fails to evaluate"
}

@test "warns but continues without the agenix key" {
  rm "$HOME/.ssh/agenix/id_ed25519"
  stub home-manager
  run bash "$UTILS/bootstrap.sh" home
  [ "$status" -eq 0 ]
  assert_output_contains "WARN: missing $HOME/.ssh/agenix/id_ed25519"
}

@test "rejects an unknown mode" {
  run bash "$UTILS/bootstrap.sh" nonsense
  [ "$status" -eq 1 ]
  assert_output_contains "Usage:"
}

## ── home ────────────────────────────────────────────────────────────────────

@test "home is a no-op when home-manager is installed" {
  stub home-manager
  run bash "$UTILS/bootstrap.sh" home
  [ "$status" -eq 0 ]
  assert_output_contains "bootstrap is a no-op"
  refute_logged "nix run"
}

@test "home runs home-manager from its flake and tags the commit" {
  run bash "$UTILS/bootstrap.sh" home
  [ "$status" -eq 0 ]
  assert_logged "nix run github:nix-community/home-manager -- switch --flake .#testhost --show-trace -b backup"
  [[ "$(tags)" =~ ^bootstrap-buildable- ]]
}

## ── host: Linux ─────────────────────────────────────────────────────────────

@test "host on Linux runs nixos-rebuild switch via sudo" {
  stub uname 'echo Linux'
  stub nixos-rebuild
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 0 ]
  assert_logged "sudo nixos-rebuild switch --flake .#testhost --show-trace --accept-flake-config"
  [[ "$(tags)" =~ ^bootstrap-buildable- ]]
}

@test "host mode can be given explicitly" {
  stub uname 'echo Linux'
  stub nixos-rebuild
  run bash "$UTILS/bootstrap.sh" host
  assert_output_contains "BOOTSTRAP (NIXOS: testhost)"
}

@test "host on Linux prefers nix-on-droid when present" {
  stub uname 'echo Linux'
  stub nix-on-droid
  stub nixos-rebuild
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 0 ]
  assert_logged "nix-on-droid switch --flake .#testhost --show-trace"
  refute_logged "nixos-rebuild"
}

@test "host on Linux without NixOS tooling fails" {
  stub uname 'echo Linux'
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 1 ]
  assert_output_contains "nixos-rebuild not found"
}

@test "host on Linux does not tag and fails when the rebuild fails" {
  stub uname 'echo Linux'
  stub nixos-rebuild 'exit 2'
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -ne 0 ]
  [ -z "$(tags)" ]
}

## ── host: Darwin ────────────────────────────────────────────────────────────

@test "host on Darwin installs Xcode CLT first" {
  stub uname 'echo Darwin'
  stub xcode-select '[ "$1" = -p ] && exit 2; exit 0'
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 1 ]
  assert_logged "xcode-select --install"
  refute_logged "nix build"
}

@test "host on Darwin is a no-op when darwin-rebuild exists" {
  stub uname 'echo Darwin'
  stub xcode-select 'echo /Library/Developer/CommandLineTools'
  stub darwin-rebuild
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 0 ]
  assert_output_contains "bootstrap is a no-op"
  refute_logged "nix build"
}

@test "host on Darwin builds the system then switches with the built darwin-rebuild" {
  stub uname 'echo Darwin'
  stub xcode-select 'echo /Library/Developer/CommandLineTools'
  mkdir -p "$REPO/result/sw/bin"
  printf '#!%s\nprintf "%%s %%s\\n" built-darwin-rebuild "$*" >>"$STUB_LOG"\n' "$BASH" >"$REPO/result/sw/bin/darwin-rebuild"
  chmod +x "$REPO/result/sw/bin/darwin-rebuild"
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 0 ]
  assert_logged "nix build --show-trace --accept-flake-config .#darwinConfigurations.testhost.system"
  assert_logged "built-darwin-rebuild switch --flake .#testhost"
}

@test "host on Darwin does not switch when the build fails" {
  stub uname 'echo Darwin'
  stub xcode-select 'echo /Library/Developer/CommandLineTools'
  export NIX_BUILD_RC=1
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -ne 0 ]
  refute_logged "sudo"
  [ -z "$(tags)" ]
}

@test "host on an unsupported OS fails" {
  stub uname 'echo FreeBSD'
  run bash "$UTILS/bootstrap.sh"
  [ "$status" -eq 1 ]
  assert_output_contains "Unsupported OS: FreeBSD"
}
