#!/usr/bin/env bash
# Remote first-install bootstrap for NixOS hosts via nixos-anywhere.
#
# This is intentionally separate from bootstrap.sh: it runs nixos-anywhere and
# can destroy target disks. Use deploy-rs for steady-state changes after install.
#
# Hardened after a real wedge: a prior run looped forever on a post-kexec SSH
# auth failure with nothing bounding it. So this wrapper (1) caps the whole
# nixos-anywhere run with a timeout, (2) bypasses host-key checks (a fresh
# install inherently trusts and wipes the target, and the host key changes
# across kexec/reboot), (3) keeps the SSH control connection alive across long
# remote builds, and (4) auto-confirms disk destruction when --yes-destroy-disk
# is passed so the run is fully headless.
#
# The script is deliberately host-agnostic: no hostnames, IPs, or IPv6 logic.
# All target specifics arrive via flags (--target, --port, --disk, ...).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# Hard cap (minutes) so a wedged install aborts instead of looping forever.
default_timeout_minutes=120

usage() {
  cat <<'EOF'
Usage:
  bootstrap-remote <host> --target <ssh-target> --check [options]
  bootstrap-remote <host> --target <ssh-target> --yes-destroy-disk [options]

Arguments:
  <host>                  Host attr under .#nixosConfigurations.<host>.

Options:
  --target <ssh-target>   SSH target for rescue/current Linux, e.g. root@203.0.113.10.
  --check                 Run local/remote preflight checks only; do not install.
  --yes-destroy-disk      Confirm nixos-anywhere may partition/format disks.
                          Also exports DISKO_NO_CONFIRM=1 so the run is headless.
  --disk <path>           Block device to check before install; default: /dev/sda.
  --agenix-identity <path>
                          Copy this local private key to /var/lib/agenix/id_ed25519.
  --no-agenix             Do not seed an agenix identity with --extra-files.
  --build-on <mode>       nixos-anywhere build mode: remote, local, or auto. Default: remote.
  --port <port>           SSH port.
  --ssh-identity <path>   SSH identity for reaching the rescue/current system.
  --ssh-option <KEY=VALUE>
                          Extra SSH option appended to the built-in defaults.
  --timeout-minutes <n>   Hard cap for the nixos-anywhere run. Default: 120.
  -h, --help              Show this help.

Environment:
  AGENIX_IDENTITY_PATH    Default for --agenix-identity when set.

SSH defaults (a fresh install trusts the target):
  StrictHostKeyChecking=no, UserKnownHostsFile=/dev/null (host key changes across
  kexec/reboot), plus keepalive ServerAliveInterval=15 / ServerAliveCountMax=240
  to survive long remote builds.

Notes:
  Non-root SSH targets must have passwordless sudo; preflight checks sudo -n true
  before nixos-anywhere is allowed to run.
EOF
}

host=""
target=""
target_disk="/dev/sda"
check_only=false
destroy_confirmed=false
seed_agenix=true
agenix_identity="${AGENIX_IDENTITY_PATH:-}"
build_on="remote"
port=""
ssh_identity=""
ssh_options=()
timeout_minutes="$default_timeout_minutes"

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z $value ]]; then
    red "Missing value for $option."
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --target)
    require_value "$1" "${2:-}"
    target="$2"
    shift
    ;;
  --check)
    check_only=true
    ;;
  --yes-destroy-disk)
    destroy_confirmed=true
    ;;
  --disk)
    require_value "$1" "${2:-}"
    target_disk="$2"
    shift
    ;;
  --agenix-identity)
    require_value "$1" "${2:-}"
    agenix_identity="$2"
    seed_agenix=true
    shift
    ;;
  --no-agenix)
    seed_agenix=false
    ;;
  --build-on)
    require_value "$1" "${2:-}"
    build_on="$2"
    shift
    ;;
  --port)
    require_value "$1" "${2:-}"
    port="$2"
    shift
    ;;
  --ssh-identity)
    require_value "$1" "${2:-}"
    ssh_identity="$2"
    shift
    ;;
  --ssh-option)
    require_value "$1" "${2:-}"
    ssh_options+=("$2")
    shift
    ;;
  --timeout-minutes)
    require_value "$1" "${2:-}"
    timeout_minutes="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    red "Unknown option: $1"
    usage
    exit 1
    ;;
  *)
    if [[ -n $host ]]; then
      red "Host specified more than once."
      usage
      exit 1
    fi
    host="$1"
    ;;
  esac
  shift
done

if [[ -z $host ]]; then
  red "Choose a host from .#nixosConfigurations."
  usage
  exit 1
fi

if [[ -z $target ]]; then
  red "Missing --target <ssh-target>."
  yellow "Example: bootstrap-remote $host --target root@203.0.113.10 --check"
  exit 1
fi

if [[ $check_only == true && $destroy_confirmed == true ]]; then
  red "Use either --check or --yes-destroy-disk, not both."
  exit 1
fi

if [[ $check_only == false && $destroy_confirmed == false ]]; then
  red "Refusing to run destructive install without --yes-destroy-disk."
  yellow "Run with --check first to validate the target without changing it."
  exit 1
fi

case "$build_on" in
remote | local | auto)
  ;;
*)
  red "Invalid --build-on value: $build_on"
  yellow "Use one of: remote, local, auto."
  exit 1
  ;;
esac

if ! [[ $timeout_minutes =~ ^[0-9]+$ ]] || ((timeout_minutes < 1)); then
  red "Invalid --timeout-minutes value: $timeout_minutes"
  yellow "Use a positive integer number of minutes."
  exit 1
fi

if [[ ! $target_disk =~ ^/dev/[A-Za-z0-9._/:+=@-]+$ ]]; then
  red "Unsafe --disk path: $target_disk"
  yellow "Use an absolute /dev path without shell metacharacters or whitespace."
  exit 1
fi

if [[ $seed_agenix == true && -z $agenix_identity ]]; then
  agenix_identity="$HOME/.ssh/agenix/id_ed25519"
fi

# A fresh install trusts and wipes the target, so bypass host-key verification
# (the key changes across kexec/reboot) and keep the connection alive for the
# long remote build. User --ssh-option values are appended on top of these.
base_ssh_options=(
  StrictHostKeyChecking=no
  UserKnownHostsFile=/dev/null
  ServerAliveInterval=15
  ServerAliveCountMax=240
  ConnectTimeout=10
)

ssh_args=(-o BatchMode=yes)
for opt in "${base_ssh_options[@]}" "${ssh_options[@]}"; do
  ssh_args+=(-o "$opt")
done
if [[ -n $port ]]; then
  ssh_args+=(-p "$port")
fi
if [[ -n $ssh_identity ]]; then
  ssh_args+=(-i "$ssh_identity")
fi

nixos_anywhere_args=(--flake ".#$host" --build-on "$build_on")
for opt in "${base_ssh_options[@]}" "${ssh_options[@]}"; do
  nixos_anywhere_args+=(--ssh-option "$opt")
done
if [[ -n $port ]]; then
  nixos_anywhere_args+=(-p "$port")
fi
if [[ -n $ssh_identity ]]; then
  nixos_anywhere_args+=(-i "$ssh_identity")
fi

remote_sudo=()

normalize_arch() {
  case "$1" in
  x86_64 | amd64)
    printf 'x86_64-linux'
    ;;
  aarch64 | arm64)
    printf 'aarch64-linux'
    ;;
  *)
    printf '%s' "$1"
    ;;
  esac
}

remote() {
  ssh "${ssh_args[@]}" "$target" "$@"
}

remote_root() {
  ssh "${ssh_args[@]}" "$target" "${remote_sudo[@]}" "$@"
}

check_target_user() {
  local target_uid

  target_uid="$(remote 'id -u')"
  green "Remote UID: $target_uid"

  if [[ $target_uid == "0" ]]; then
    remote_sudo=()
    return
  fi

  yellow "Remote target is non-root; requiring passwordless sudo."
  remote 'sudo -n true'
  remote_sudo=(sudo -n)
}

check_target_platform() {
  local configured_system remote_machine remote_system

  configured_system="$(nix eval --raw --show-trace --accept-flake-config ".#nixosConfigurations.$host.pkgs.stdenv.hostPlatform.system")"
  remote_machine="$(remote 'uname -m')"
  remote_system="$(normalize_arch "$remote_machine")"

  green "Configured host platform: $configured_system"
  green "Remote machine platform: $remote_machine ($remote_system)"

  if [[ $configured_system != "$remote_system" ]]; then
    red "Configured platform ($configured_system) does not match remote uname -m ($remote_machine)."
    exit 1
  fi
}

check_target_disk() {
  green "Resolving target disk: $target_disk"
  remote_root readlink -f "$target_disk"

  green "Checking target disk exists: $target_disk"
  remote_root test -b "$target_disk"

  green "Target disk identity and size:"
  remote_root lsblk -d -o NAME,PATH,MODEL,SERIAL,SIZE,TYPE "$target_disk"
}

run_preflight_checks() {
  green "====== NIXOS REMOTE BOOTSTRAP PREFLIGHT ($host) ======"

  if [[ ! -f "$PWD/flake.nix" ]]; then
    red "No flake.nix in current directory ($PWD)."
    yellow "cd into the infra-nixCfg repo root before running bootstrap-remote."
    exit 1
  fi
  green "Repository root: $PWD"

  if ! command -v nix >/dev/null 2>&1; then
    red "nix is not available on PATH."
    exit 1
  fi
  green "Nix: $(nix --version | head -n1)"

  if ! command -v nixos-anywhere >/dev/null 2>&1; then
    red "nixos-anywhere is not available on PATH."
    yellow "Enter the project devshell first (nix develop) or run via: nix shell nixpkgs#nixos-anywhere -c bash $0 ..."
    exit 1
  fi
  green "nixos-anywhere: $(nixos-anywhere --version 2>/dev/null || command -v nixos-anywhere)"

  if [[ $seed_agenix == true ]]; then
    if [[ ! -f $agenix_identity ]]; then
      red "Missing agenix identity: $agenix_identity"
      yellow "Pass --agenix-identity <path>, set AGENIX_IDENTITY_PATH, or use --no-agenix."
      exit 1
    fi
    green "agenix identity exists: $agenix_identity"
  else
    yellow "Skipping agenix identity seeding."
  fi

  green "Evaluating .#nixosConfigurations.$host.config.system.build.toplevel"
  nix eval --raw --show-trace --accept-flake-config ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null

  green "Checking SSH connectivity: $target"
  local remote_hostname
  remote_hostname="$(remote 'hostname')"
  green "SSH OK; remote hostname: $remote_hostname"
  if [[ $remote_hostname == "nixos-installer" || $remote_hostname == "nixos" ]]; then
    yellow "Target is already a kexec-installer; nixos-anywhere will skip kexec and go straight to disko/install."
  fi

  check_target_user
  check_target_platform
  check_target_disk
}

run_install() {
  local extra_files=""
  local cleanup=()

  if [[ $seed_agenix == true ]]; then
    extra_files="$(mktemp -d)"
    cleanup+=("$extra_files")
    install -D -m 0600 "$agenix_identity" "$extra_files/var/lib/agenix/id_ed25519"
    nixos_anywhere_args+=(--extra-files "$extra_files")
  fi

  yellow "About to run nixos-anywhere for $host against $target."
  yellow "This may partition/format disks according to the selected NixOS configuration."
  yellow "Preflight checked target disk: $target_disk."

  # --yes-destroy-disk is the user's explicit confirmation; headless-confirm disk
  # destruction so no interactive prompt can wedge the run.
  if [[ $destroy_confirmed == true ]]; then
    export DISKO_NO_CONFIRM=1
  fi

  # Bound the run so an auth/reconnect hiccup cannot loop forever (prior wedge).
  if command -v timeout >/dev/null 2>&1; then
    timeout -s TERM -k 60s "${timeout_minutes}m" \
      nixos-anywhere "${nixos_anywhere_args[@]}" "$target"
  else
    yellow "GNU 'timeout' not found on PATH — running unbounded (install coreutils to enable the hard cap)."
    nixos-anywhere "${nixos_anywhere_args[@]}" "$target"
  fi

  # Clean up seeded agenix temp dirs only on success (on failure, leave them for inspection).
  for d in "${cleanup[@]}"; do
    rm -rf "$d"
  done
}

on_error() {
  local rc=$?
  red "bootstrap-remote FAILED for $host (exit $rc)."
  if [[ $rc -eq 124 ]]; then
    red "Hit the ${timeout_minutes}m timeout — killed to avoid hanging forever."
    yellow "Re-run once the target is reachable; an already-kexeced target skips the problematic kexec phase."
  fi
}
trap on_error ERR

run_preflight_checks

if [[ $check_only == true ]]; then
  green "Preflight passed; no destructive action was taken."
  exit 0
fi

run_install
green "====== bootstrap-remote SUCCEEDED for $host ======"
