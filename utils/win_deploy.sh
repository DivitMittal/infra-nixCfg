#!/usr/bin/env bash
# Deploy a Windows host's NixOS-WSL distro and its nix-win configuration from
# a workstation, over the Windows host's own OpenSSH server.
#
#   win-deploy L2              # rebuild L2W, then nix-win switch for l2
#   win-deploy L2 --wsl-only   # only the NixOS-WSL distro
#   win-deploy L2 --win-only   # only nix-win
#   win-deploy L2 --build      # nix-win build, no activation
#
# Why not deploy-rs: the SSH target is Windows, which has no Nix to receive a
# closure. Windows OpenSSH admin sessions are elevated, so nix-win's
# machine-scope registry writes work without a scheduled-task detour.
#
# Why the store import: the flake has a private input (infra-nixCfg-secrets)
# that WSL can't fetch without GitHub credentials. The committed flake source
# and that input are exported from this machine's store and imported into
# the distro, and every build overrides the input with the imported copy.
set -euo pipefail

usage() {
  echo "usage: win-deploy <host> [--wsl-only|--win-only|--build]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
host="$1"
mode="${2:-all}"

## Per-host settings
case "$host" in
L2)
  target="vanee@192.168.2.6" # T640 router reservation
  distro="NixOS"
  wsl_user="vanee"
  wsl_attr="L2W"
  win_attr="l2"
  ;;
*)
  echo "win-deploy: unknown host '$host'" >&2
  exit 2
  ;;
esac

case "$mode" in
all | --wsl-only | --win-only | --build) ;;
*) usage ;;
esac

ssh_key="${WIN_DEPLOY_SSH_KEY:-$HOME/.ssh/agenix/id_ed25519}"
ssh_opts=(-o BatchMode=yes -o ServerAliveInterval=15 -i "$ssh_key" -o IdentitiesOnly=yes)
remote() { ssh "${ssh_opts[@]}" "$target" "$@"; }
# Run a command as root in the distro. sh -c, not -lc: a login shell prints
# NixOS-WSL's welcome banner into the output.
in_wsl() { remote "wsl -d $distro -u root -- /bin/sh -c \"PATH=/run/current-system/sw/bin; $1\""; }

## Pin the committed tree: uncommitted edits are not deployed.
root=$(git rev-parse --show-toplevel)
rev=$(git -C "$root" rev-parse HEAD)
if [ -n "$(git -C "$root" status --porcelain)" ]; then
  echo "win-deploy: deploying $rev; uncommitted changes are not included" >&2
fi

archive=$(nix flake archive --dry-run --json "git+file://$root?rev=$rev")
src=$(jq -r .path <<<"$archive")
secrets=$(jq -r '.inputs["infra-nixCfg-secrets"].path' <<<"$archive")
nixwin_rev=$(jq -r '.nodes["nix-win"].locked.rev' "$root/flake.lock")
nix_flags="--extra-experimental-features 'nix-command flakes' --option accept-flake-config false --override-input infra-nixCfg-secrets path:$secrets"

echo "win-deploy: importing $rev into $host's $distro store..."
nix-store --export "$src" "$secrets" | in_wsl "nix-store --import >/dev/null"

if [ "$mode" = all ] || [ "$mode" = --wsl-only ]; then
  echo "win-deploy: switching $distro to .#$wsl_attr..."
  in_wsl "nixos-rebuild switch $nix_flags --flake path:$src#$wsl_attr"
fi

[ "$mode" = --wsl-only ] && exit 0

## nix-win builds by itself through `wsl.exe -u <user>`; it can't take
## --override-input, so the switch below builds the config first with the
## override (as that user), which leaves nothing for nix-win to fetch.
echo "win-deploy: building winConfigurations.$win_attr..."
remote "wsl -d $distro -u $wsl_user -- /bin/sh -c \"PATH=/run/current-system/sw/bin; nix build --no-link $nix_flags path:$src#winConfigurations.$win_attr.config.system.build.toplevel\""

cli=$(in_wsl "nix build --no-link --print-out-paths --extra-experimental-features 'nix-command flakes' github:jacobbrugh/nix-win/$nixwin_rev#nix-win" | tr -d '\r' | tail -1)
cli_win="\\\\wsl.localhost\\$distro${cli//\//\\}\\nix-win.ps1"

command="switch"
[ "$mode" = --build ] && command="build"
echo "win-deploy: nix-win $command on $host..."
remote "pwsh -NoProfile -ExecutionPolicy Bypass -File \"$cli_win\" $command -FlakeUri \"path:$src\" -FlakeAttr winConfigurations.$win_attr -WslDistro $distro -WslUser $wsl_user"
