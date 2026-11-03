#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# Rebuild & switch the home-manager configuration.
# Assumes `home-manager` is already installed — run
# ./utils/bootstrap.sh home once on a fresh machine to get there.
#
# SC2086 is ignored because we purposefully word-split $switch_args.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

switch_args=$(build_switch_args "$@")

green "====== REBUILDING & SWITCHING (HOME) ======"

if ! command -v home-manager &>/dev/null; then
  red "home-manager not found."
  yellow "Run ./utils/bootstrap.sh home once to install it."
  exit 1
fi

echo $switch_args
home-manager $switch_args
status=$?

if [ "$status" -eq 0 ]; then
  post_rebuild_success "home"
fi
exit "$status"
