#!/usr/bin/env bash
# One-time: copies this machine's shared homelab SSH identity onto L2's
# Windows boot slot (user vanee), so `ssh L1` from there (the alias
# hosts/win/L2/main.nix declares) can actually authenticate — L1
# (hosts/darwin/L1/services/ssh.nix) already trusts this same pubkey, the
# one every other home-lab box shares (hosts/nixos/_homelab/base.nix).
#
# nix-win can't deploy the private half itself without committing it to the
# store, so this has to run out of band, from a box that already holds it
# (L1, T2, T3, ...):
#
#   utils/provision_l2_ssh_key.sh
#
# Safe to re-run; it overwrites the remote copy and re-applies the ACL.
set -euo pipefail

target="vanee@192.168.2.6"
identity="${L2_SSH_IDENTITY:-$HOME/.ssh/agenix/id_ed25519}"
ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$identity" -o IdentitiesOnly=yes)

## The remote default shell is cmd.exe (not PowerShell) — plain cmd syntax,
## no nested-quoting through powershell -Command (that's the gotcha
## nix-win-dsc-gotchas warns about; use -EncodedCommand if this ever needs
## real PowerShell).
ssh "${ssh_opts[@]}" "$target" 'if not exist .ssh mkdir .ssh'
scp -q "${ssh_opts[@]}" "$identity" "$identity.pub" "$target:.ssh/"
# Win32-OpenSSH refuses a private key readable by anyone but its owner.
ssh "${ssh_opts[@]}" "$target" \
  'icacls "%USERPROFILE%\.ssh\id_ed25519" /inheritance:r /grant:r %USERNAME%:F'

echo "Copied $(basename "$identity") to $target:.ssh/. Verify with: ssh $target ssh L1 true"
