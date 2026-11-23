#!/usr/bin/env bash
# Bootstrap the Sway login with T2's declared virtual keyboard. Password input
# stays inside an interactive SSH terminal and is never passed as an argument.
set -euo pipefail

identity="${T2_SSH_IDENTITY:-$HOME/.ssh/agenix/id_ed25519}"
ssh_args=(-o BatchMode=yes -o ConnectTimeout=7 -i "$identity" root@192.168.2.171)

ssh "${ssh_args[@]}" 'umask 077; cat > /run/lan-mouse-console-login' <<'REMOTE'
set -euo pipefail
trap 'unset login_password; rm -f /run/lan-mouse-console-login' EXIT

if pgrep -u "$(id -u div)" -x sway >/dev/null; then
  printf 'T2 already has a Sway desktop session.\n'
  exit 0
fi
systemctl is-active --quiet ydotoold
systemctl is-active --quiet greetd
export YDOTOOL_SOCKET=/run/ydotoold/socket

IFS= read -r -s -p 'T2 div login password (not echoed): ' login_password
printf '\n'
if [[ -z "$login_password" ]]; then
  printf 'No password entered; leaving the login screen unchanged.\n' >&2
  exit 1
fi

# Reset the greeter so the password cannot be typed into a stale username field.
systemctl restart greetd
chvt 1
sleep 1
ydotool type div
ydotool key 28:1 28:0
sleep 1
printf '%s' "$login_password" | ydotool type --file -
unset login_password
ydotool key 28:1 28:0

for attempt in {1..15}; do
  if pgrep -u "$(id -u div)" -x sway >/dev/null; then
    printf 'T2 started Sway. Move the Mac pointer through its left edge.\n'
    exit 0
  fi
  sleep 1
done
printf 'Sway did not start. Check T2’s display for the login result.\n' >&2
exit 1
REMOTE

ssh -t "${ssh_args[@]}" 'bash /run/lan-mouse-console-login'
