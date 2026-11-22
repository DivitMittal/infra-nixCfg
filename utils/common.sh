#!/usr/bin/env bash
# Common functions for rebuild scripts

# Colored output functions
function red() {
  echo -e "\x1B[31m[!] $1 \x1B[0m"
  if [ -n "${2-}" ]; then
    echo -e "\x1B[31m[!] $($2) \x1B[0m"
  fi
}

function green() {
  echo -e "\x1B[32m[+] $1 \x1B[0m"
  if [ -n "${2-}" ]; then
    echo -e "\x1B[32m[+] $($2) \x1B[0m"
  fi
}

function yellow() {
  echo -e "\x1B[33m[*] $1 \x1B[0m"
  if [ -n "${2-}" ]; then
    echo -e "\x1B[33m[*] $($2) \x1B[0m"
  fi
}

# Refuse to pick the t640's T2 config on L1's NixOS.
# Usage: refuse_stale_l1n_hostname <hostname>
#
# L1's NixOS was installed as host "T2"; that name now belongs to an HP t640
# (nixosConfigurations.T2 / homeConfigurations.T2) and the MacBook's config is
# L1N. Until L1's NixOS is switched once to .#L1N its hostname is still T2, so
# selecting the flake attribute by hostname would apply the t640's disks,
# bootloader and k3s role to the MacBook. A real t640 reports vendor HP, so
# only the Apple + T2 combination is refused.
function refuse_stale_l1n_hostname() {
  local host="$1" vendor=""
  [[ $host == "T2" ]] || return 0
  [[ -r /sys/class/dmi/id/sys_vendor ]] && vendor="$(</sys/class/dmi/id/sys_vendor)"
  [[ $vendor == Apple* ]] || return 0

  red "Hostname is T2 but this is Apple hardware: this is L1's NixOS, not the HP t640."
  yellow "Switch it once to its renamed config, from the repo root:"
  yellow "  sudo nixos-rebuild switch --flake .#L1N"
  yellow "The hostname becomes L1N; afterwards hts/hms select L1N automatically."
  exit 1
}

# Build switch arguments
# Usage: build_switch_args [additional_flags...]
function build_switch_args() {
  local args="$*"
  args="$args --keep-going --flake .#$(hostname) switch"
  echo "$args"
}

# Post-rebuild success handler
# Usage: post_rebuild_success <tag_prefix>
function post_rebuild_success() {
  local tag_prefix="${1:-buildable}"

  green "====== POST-REBUILD ======"
  green "Rebuilt successfully"

  # Check if there are any pending changes that would affect the build succeeding.
  if git diff --exit-code >/dev/null && git diff --staged --exit-code >/dev/null; then
    # Check if the current commit has a buildable tag
    if git tag --points-at HEAD | grep -q buildable; then
      yellow "Current commit is already tagged as buildable"
    else
      git tag "${tag_prefix}-buildable-$(date +%Y%m%d%H%M%S)" -m ''
      green "Tagged current commit as buildable"
    fi
  else
    yellow "WARN: There are pending changes that would affect the build succeeding. Commit them before tagging"
  fi
}
