#!/usr/bin/env bash
# Read-only inventory; stable identifiers and SMART details stay out of stdout.
set -euo pipefail
if [[ $(uname -s) == Darwin ]]; then
  exec /usr/sbin/diskutil list
fi
if [[ $EUID != 0 ]]; then
  echo 'Run as root to inspect filesystem signatures without mounting.' >&2
  exit 1
fi
lsblk -e 7 -o NAME,SIZE,TYPE,TRAN,ROTA,FSTYPE,MOUNTPOINTS
findmnt --real -rn -o TARGET,FSTYPE
while read -r device transport; do
  [[ $transport == usb ]] || continue
  echo "USB device: $device"
  udevadm info --query=property --name="$device" |
    sed -n '/^ID_BUS=/p; /^ID_USB_DRIVER=/p; /^ID_ATA_ROTATION_RATE_RPM=/p'
  while read -r member; do
    # No UUID/label output: only signature type and offset, including stale data.
    if ! wipefs --no-act --noheadings --output TYPE,OFFSET "$member"; then
      echo "Signature probe unavailable for $member (possibly no media)." >&2
    fi
  done < <(lsblk -nrpo NAME "$device")
  if command -v smartctl >/dev/null && command -v python3 >/dev/null; then
    # Health only: never start a self-test or change drive settings.
    # Nonzero bitmasks can indicate unsupported bridges, standby or bad health.
    status=0
    smartctl -n standby -H -j "$device" | python3 -c '
import json, sys
x = json.load(sys.stdin)
print("SMART health:", x.get("smart_status", {}).get("passed", "unknown"))
' || status=$?
    if ((status)); then
      echo "SMART unavailable or unhealthy (status $status); review privately." >&2
    fi
  else
    echo 'smartctl or python3 unavailable; SMART status unknown.' >&2
  fi
done < <(lsblk -dnpo NAME,TRAN)
