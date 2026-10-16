#!/usr/bin/env bats
# utils/bootstrap_remote.sh — everything is stubbed; no SSH or disk is touched.

setup() {
  load helpers
  setup_sandbox
  init_repo
  cd "$REPO"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.ssh/agenix"
  echo secret-key >"$HOME/.ssh/agenix/id_ed25519"
  unset AGENIX_IDENTITY_PATH

  # Remote side, driven by env: REMOTE_UID / REMOTE_ARCH / REMOTE_HOSTNAME.
  stub ssh 'cmd="${*: -1}"
    case "$cmd" in
      "id -u") echo "${REMOTE_UID:-0}" ;;
      "uname -m") echo "${REMOTE_ARCH:-x86_64}" ;;
      hostname) echo "${REMOTE_HOSTNAME:-rescue}" ;;
    esac'
  stub nix 'case "$*" in
    --version) echo "nix (Nix) 2.99" ;;
    *hostPlatform.system*) printf %s "${CONFIGURED_SYSTEM:-x86_64-linux}" ;;
    *) echo /nix/store/fake.drv ;;
  esac'
  stub nixos-anywhere 'echo "DISKO_NO_CONFIRM=${DISKO_NO_CONFIRM:-unset}" >>"$STUB_LOG"
    for ((i = 1; i <= $#; i++)); do
      if [ "${!i}" = --extra-files ]; then j=$((i + 1)); cat "${!j}/var/lib/agenix/id_ed25519" >>"$STUB_LOG"; fi
    done
    exit "${NA_RC:-0}"'
  stub timeout 'shift 5; exec "$@"'
}

remote() {
  run bash "$UTILS/bootstrap_remote.sh" "$@"
}

## ── argument validation ─────────────────────────────────────────────────────

@test "--help prints usage and succeeds" {
  remote --help
  [ "$status" -eq 0 ]
  assert_output_contains "Usage:"
  assert_output_contains "--yes-destroy-disk"
}

@test "requires a host" {
  remote --target root@h --check
  [ "$status" -eq 1 ]
  assert_output_contains "Choose a host"
}

@test "requires --target" {
  remote VPS1 --check
  [ "$status" -eq 1 ]
  assert_output_contains "Missing --target"
}

@test "rejects a host given twice" {
  remote VPS1 VPS2 --target root@h --check
  [ "$status" -eq 1 ]
  assert_output_contains "Host specified more than once."
}

@test "rejects unknown options" {
  remote VPS1 --target root@h --check --frobnicate
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown option: --frobnicate"
}

@test "rejects options missing their value" {
  remote VPS1 --check --target
  [ "$status" -eq 1 ]
  assert_output_contains "Missing value for --target."
}

@test "refuses a destructive run without --yes-destroy-disk" {
  remote VPS1 --target root@h
  [ "$status" -eq 1 ]
  assert_output_contains "Refusing to run destructive install"
  refute_logged "ssh"
}

@test "refuses --check together with --yes-destroy-disk" {
  remote VPS1 --target root@h --check --yes-destroy-disk
  [ "$status" -eq 1 ]
  assert_output_contains "either --check or --yes-destroy-disk"
}

@test "validates --build-on" {
  remote VPS1 --target root@h --check --build-on cloud
  [ "$status" -eq 1 ]
  assert_output_contains "Invalid --build-on value: cloud"
}

@test "accepts every documented --build-on mode" {
  for mode in remote local auto; do
    remote VPS1 --target root@h --check --build-on "$mode"
    [ "$status" -eq 0 ]
  done
}

@test "validates --timeout-minutes" {
  for bad in 0 -5 abc 1.5; do
    remote VPS1 --target root@h --check --timeout-minutes "$bad"
    [ "$status" -eq 1 ]
    assert_output_contains "Invalid --timeout-minutes value"
  done
}

@test "rejects disk paths with shell metacharacters" {
  for bad in "/dev/sda; rm -rf /" "sda" "/dev/sd a" '/dev/$(id)'; do
    remote VPS1 --target root@h --check --disk "$bad"
    [ "$status" -eq 1 ]
    assert_output_contains "Unsafe --disk path"
  done
}

@test "accepts by-id disk paths" {
  remote VPS1 --target root@h --check --disk /dev/disk/by-id/nvme-Samsung_SSD_980-part1
  [ "$status" -eq 0 ]
}

## ── preflight (--check) ─────────────────────────────────────────────────────

@test "--check runs preflight without installing" {
  remote VPS1 --target root@h --check
  [ "$status" -eq 0 ]
  assert_output_contains "no destructive action was taken"
  assert_logged "nix eval --raw --show-trace --accept-flake-config .#nixosConfigurations.VPS1.config.system.build.toplevel.drvPath"
  assert_logged "readlink -f /dev/sda"
  refute_logged "nixos-anywhere --flake"
}

@test "preflight refuses to run outside the repo root" {
  rm "$REPO/flake.nix"
  remote VPS1 --target root@h --check
  [ "$status" -eq 1 ]
  assert_output_contains "No flake.nix"
}

@test "preflight requires nixos-anywhere" {
  rm "$STUB_BIN/nixos-anywhere"
  remote VPS1 --target root@h --check
  [ "$status" -eq 1 ]
  assert_output_contains "nixos-anywhere is not available"
}

@test "preflight requires the agenix identity unless --no-agenix" {
  rm "$HOME/.ssh/agenix/id_ed25519"
  remote VPS1 --target root@h --check
  [ "$status" -eq 1 ]
  assert_output_contains "Missing agenix identity"

  remote VPS1 --target root@h --check --no-agenix
  [ "$status" -eq 0 ]
}

@test "AGENIX_IDENTITY_PATH overrides the default identity" {
  echo env-key >"$BATS_TEST_TMPDIR/env-key"
  rm "$HOME/.ssh/agenix/id_ed25519"
  AGENIX_IDENTITY_PATH="$BATS_TEST_TMPDIR/env-key" remote VPS1 --target root@h --check
  [ "$status" -eq 0 ]
}

@test "preflight aborts on a platform mismatch" {
  export REMOTE_ARCH=aarch64
  remote VPS1 --target root@h --check
  [ "$status" -eq 1 ]
  assert_output_contains "does not match remote uname -m"
}

@test "preflight normalises arm64 to aarch64-linux" {
  export REMOTE_ARCH=arm64 CONFIGURED_SYSTEM=aarch64-linux
  remote VPS0 --target root@h --check
  [ "$status" -eq 0 ]
}

@test "non-root targets must have passwordless sudo and disk checks use it" {
  export REMOTE_UID=1000
  remote VPS1 --target admin@h --check
  [ "$status" -eq 0 ]
  assert_logged "sudo -n true"
  assert_logged "admin@h sudo -n readlink -f /dev/sda"
}

@test "ssh always bypasses host keys and keeps the connection alive" {
  remote VPS1 --target root@h --check --port 2222 --ssh-identity /k --ssh-option Foo=bar
  [ "$status" -eq 0 ]
  assert_logged "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=240 -o ConnectTimeout=10 -o Foo=bar -p 2222 -i /k root@h"
}

## ── install ─────────────────────────────────────────────────────────────────

@test "install passes flake, ssh options and target to nixos-anywhere" {
  remote VPS1 --target root@h --yes-destroy-disk --build-on local --port 2222 --ssh-option Foo=bar --no-agenix
  [ "$status" -eq 0 ]
  assert_logged "nixos-anywhere --flake .#VPS1 --build-on local --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --ssh-option ServerAliveInterval=15 --ssh-option ServerAliveCountMax=240 --ssh-option ConnectTimeout=10 --ssh-option Foo=bar -p 2222 root@h"
  assert_output_contains "bootstrap-remote SUCCEEDED for VPS1"
}

@test "install confirms disk destruction headlessly" {
  remote VPS1 --target root@h --yes-destroy-disk --no-agenix
  assert_logged "DISKO_NO_CONFIRM=1"
}

@test "install is bounded by timeout" {
  remote VPS1 --target root@h --yes-destroy-disk --no-agenix --timeout-minutes 7
  assert_logged "timeout -s TERM -k 60s 7m nixos-anywhere"
}

@test "install runs unbounded with a warning when timeout is unavailable" {
  rm "$STUB_BIN/timeout"
  remote VPS1 --target root@h --yes-destroy-disk --no-agenix
  [ "$status" -eq 0 ]
  assert_output_contains "GNU 'timeout' not found"
  assert_logged "nixos-anywhere --flake .#VPS1"
}

@test "install seeds the agenix identity via --extra-files" {
  remote VPS1 --target root@h --yes-destroy-disk
  [ "$status" -eq 0 ]
  assert_logged "--extra-files"
  assert_logged "secret-key"
}

@test "install with --no-agenix seeds nothing extra" {
  remote VPS1 --target root@h --yes-destroy-disk --no-agenix
  refute_logged "--extra-files"
}

@test "install failure is reported and propagated" {
  export NA_RC=5
  remote VPS1 --target root@h --yes-destroy-disk --no-agenix
  [ "$status" -eq 5 ]
  assert_output_contains "bootstrap-remote FAILED for VPS1 (exit 5)"
}

@test "install timeout is called out explicitly" {
  export NA_RC=124
  remote VPS1 --target root@h --yes-destroy-disk --no-agenix --timeout-minutes 3
  [ "$status" -eq 124 ]
  assert_output_contains "Hit the 3m timeout"
}
