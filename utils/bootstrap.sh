#!/usr/bin/env bash
# First-time bootstrap for an infra-nixCfg host.
#
# Daily rebuilds go through utils/hosts_rebuild.sh (hts) and
# utils/home_rebuild.sh (hms). Those assume their respective rebuild tool is
# already installed. This script handles the one-shot path that gets you to
# that point on a freshly cloned machine.
#
# Usage:
#   ./utils/bootstrap.sh           # bootstrap the host (auto-detects darwin / nixos / droid)
#   ./utils/bootstrap.sh host      # same as above, explicit
#   ./utils/bootstrap.sh home      # bootstrap home-manager (standalone)
#
# Run from the repo root (a flake.nix must be in $PWD).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

HOST="$(hostname -s)"
OS="$(uname -s)"

run_preflight_checks() {
  green "====== PRE-FLIGHT CHECKS ======"

  if [[ ! -f "$PWD/flake.nix" ]]; then
    red "No flake.nix in current directory ($PWD)."
    yellow "cd into the infra-nixCfg repo root before running bootstrap."
    exit 1
  fi
  green "Repository root: $PWD"

  if ! command -v nix &>/dev/null; then
    red "Nix is not installed."
    yellow "Install via Determinate Systems:"
    yellow "  curl -fsSL https://install.determinate.systems/nix | sh -s -- install"
    exit 1
  fi
  green "Nix: $(nix --version | head -n1)"

  if ! nix flake metadata . >/dev/null 2>&1; then
    red "This flake fails to evaluate (or nix-command/flakes are disabled)."
    yellow "Ensure /etc/nix/nix.conf contains:"
    yellow "  experimental-features = nix-command flakes"
    yellow "Then re-run bootstrap. (Determinate Nix enables both by default.)"
    exit 1
  fi
  green "Flake evaluates and flakes are enabled"

  if [[ ! -f "$HOME/.ssh/agenix/id_ed25519" ]]; then
    yellow "WARN: missing $HOME/.ssh/agenix/id_ed25519"
    yellow "      Secrets from OS-nixCfg-secrets will not decrypt."
    yellow "      Place your enrolled age/SSH key at that path, or expect"
    yellow "      activation to fail on modules that consume secrets."
  else
    green "agenix SSH key present at $HOME/.ssh/agenix/id_ed25519"
  fi

  echo
}

bootstrap_darwin() {
  green "====== BOOTSTRAP (DARWIN: $HOST) ======"

  if ! xcode-select -p &>/dev/null; then
    yellow "Xcode Command-line Tools not installed."
    yellow "Launching installer (a GUI dialog will appear)."
    xcode-select --install || true
    red "After Xcode CLT installation finishes, re-run: ./utils/bootstrap.sh"
    exit 1
  fi
  green "Xcode CLT: $(xcode-select -p)"

  if command -v darwin-rebuild &>/dev/null; then
    yellow "darwin-rebuild is already installed; bootstrap is a no-op."
    yellow "Use 'hts switch' (or ./utils/hosts_rebuild.sh switch) for ongoing rebuilds."
    exit 0
  fi

  green "Building first darwin-rebuild for .#$HOST"
  if nix build --show-trace --accept-flake-config ".#darwinConfigurations.$HOST.system" &&
    sudo ./result/sw/bin/darwin-rebuild switch --flake ".#$HOST"; then
    post_rebuild_success "bootstrap"
  fi
}

bootstrap_nixos() {
  green "====== BOOTSTRAP (NIXOS: $HOST) ======"

  if ! command -v nixos-rebuild &>/dev/null; then
    red "nixos-rebuild not found — are you actually on NixOS?"
    exit 1
  fi

  green "Running first nixos-rebuild switch for .#$HOST"
  if sudo nixos-rebuild switch --flake ".#$HOST" --show-trace --accept-flake-config; then
    post_rebuild_success "bootstrap"
  fi
}

bootstrap_droid() {
  green "====== BOOTSTRAP (DROID: $HOST) ======"

  if ! command -v nix-on-droid &>/dev/null; then
    red "nix-on-droid not found."
    yellow "Install via Termux: https://github.com/nix-community/nix-on-droid"
    exit 1
  fi

  green "Running first nix-on-droid switch for .#$HOST"
  if nix-on-droid switch --flake ".#$HOST" --show-trace; then
    post_rebuild_success "bootstrap"
  fi
}

bootstrap_home() {
  green "====== BOOTSTRAP (HOME-MANAGER: $HOST) ======"

  if command -v home-manager &>/dev/null; then
    yellow "home-manager is already installed; bootstrap is a no-op."
    yellow "Use 'hms switch' (or ./utils/home_rebuild.sh switch) for ongoing rebuilds."
    exit 0
  fi

  green "Running first home-manager switch via 'nix run' for .#$HOST"
  if nix run github:nix-community/home-manager -- \
    switch \
    --flake ".#$HOST" \
    --show-trace \
    -b backup; then
    post_rebuild_success "bootstrap"
  fi
}

main() {
  run_preflight_checks

  local mode="${1:-host}"
  case "$mode" in
  host)
    case "$OS" in
    Darwin)
      bootstrap_darwin
      ;;
    Linux)
      if command -v nix-on-droid &>/dev/null; then
        bootstrap_droid
      else
        bootstrap_nixos
      fi
      ;;
    *)
      red "Unsupported OS: $OS"
      exit 1
      ;;
    esac
    ;;
  home)
    bootstrap_home
    ;;
  *)
    red "Usage: $0 [host|home]"
    exit 1
    ;;
  esac
}

main "$@"
