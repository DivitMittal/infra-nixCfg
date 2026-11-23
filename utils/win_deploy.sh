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
# closure.
#
# Why a scheduled task: nix-win copies its build output from the distro's
# \\wsl.localhost share, which an OpenSSH session can't see. A task running
# as the logged-on user (interactive, highest run level) can, and is elevated
# for nix-win's machine-scope registry writes. So that user must be logged on.
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
  win_user="vanee"
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
ssh_opts=(-o BatchMode=yes -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new -i "$ssh_key" -o IdentitiesOnly=yes)
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
# The fresh distro has flakes off, and nixos-rebuild only takes --option.
nix_flags="--option experimental-features 'nix-command flakes' --option accept-flake-config false --override-input infra-nixCfg-secrets path:$secrets"

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

command="switch"
[ "$mode" = --build ] && command="build"

console_user=$(remote 'powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).UserName"' | tr -d '\r' | tail -1)
if [ "${console_user##*\\}" != "$win_user" ]; then
  echo "win-deploy: $win_user must be logged on at $host's console (found '${console_user:-nobody}')" >&2
  exit 1
fi

## Stage the CLI and a runner on the Windows disk (through the distro's
## /mnt/c), then run the runner as a task in the user's session.
stage="/mnt/c/Users/$win_user/AppData/Local/nix-win/deploy"
stage_win="C:\\Users\\$win_user\\AppData\\Local\\nix-win\\deploy"
remote "wsl -d $distro -u $wsl_user -- /bin/sh -c \"PATH=/run/current-system/sw/bin; mkdir -p $stage && rm -f $stage/done $stage/log.txt && cp -f $cli/nix-win.ps1 $stage/nix-win.ps1 && cat > $stage/run.ps1\"" <<EOF
\$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$stage_win\\log.txt' | Out-Null
try {
  \$global:LASTEXITCODE = 0
  & '$stage_win\\nix-win.ps1' $command -FlakeUri 'path:$src' -FlakeAttr 'winConfigurations.$win_attr' -WslDistro '$distro' -WslUser '$wsl_user'
  \$code = if (\$LASTEXITCODE) { \$LASTEXITCODE } else { 0 }
} catch {
  Write-Host \$_
  \$code = 1
}
Stop-Transcript | Out-Null
Set-Content -Path '$stage_win\\done' -Value \$code
EOF

echo "win-deploy: nix-win $command on $host..."
remote "schtasks /create /f /tn nix-win-deploy /sc once /st 23:59 /ru $win_user /it /rl highest /tr \"pwsh -NoProfile -ExecutionPolicy Bypass -File $stage_win\\run.ps1\" >nul && schtasks /run /tn nix-win-deploy >nul"

for _ in $(seq 1 360); do
  code=$(remote "type $stage_win\\done 2>nul" | tr -d '\r\377\376\000' | tr -d '[:space:]' || true)
  [ -n "$code" ] && break
  sleep 10
done
remote "type $stage_win\\log.txt & schtasks /delete /f /tn nix-win-deploy >nul" | tr -d '\r\000'
if [ -z "${code:-}" ]; then
  echo "win-deploy: nix-win did not finish within an hour" >&2
  exit 1
fi
exit "$code"
