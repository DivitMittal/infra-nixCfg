#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# Rebuild & switch the host (NixOS / nix-darwin / nix-on-droid) configuration.
# Assumes the platform rebuild tool is already installed — run
# ./utils/bootstrap.sh once on a fresh machine to get there.
#
# SC2086 is ignored because we purposefully word-split $switch_args.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

refuse_stale_l1n_hostname "$(hostname)"
switch_args=$(build_switch_args "$@")
os=$(uname -s)

if [[ $os == "Darwin" ]]; then
  if ! command -v darwin-rebuild &>/dev/null; then
    red "darwin-rebuild not found."
    yellow "Run ./utils/bootstrap.sh once to install it."
    exit 1
  fi
  green "====== REBUILDING & SWITCHING (DARWIN) ======"
  echo $switch_args
  sudo darwin-rebuild $switch_args
elif command -v nix-on-droid &>/dev/null; then
  green "====== REBUILDING & SWITCHING (DROID) ======"
  echo $switch_args
  nix-on-droid $switch_args
elif command -v nixos-rebuild &>/dev/null; then
  green "====== REBUILDING & SWITCHING (NIXOS) ======"
  echo $switch_args
  sudo nixos-rebuild $switch_args
else
  red "No rebuild tool found (darwin-rebuild / nixos-rebuild / nix-on-droid)."
  yellow "Run ./utils/bootstrap.sh once to install one."
  exit 1
fi

# shellcheck disable=SC2181
if [ $? -eq 0 ]; then
  post_rebuild_success "host"
fi
