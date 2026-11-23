#!/usr/bin/env bash
# Capture only the properties needed to select a compatible declarative profile.
set -euo pipefail
umask 077

if [[ $# -ne 1 || -z $1 ]]; then
  echo "Usage: bash android/B1/inspect.sh ADB_SERIAL" >&2
  exit 2
fi
command -v adb >/dev/null || {
  echo "adb is required (enter nix develop)." >&2
  exit 1
}
serial=$1
[[ $(adb -s "$serial" get-state) == device ]] || {
  echo "The selected device is not ready; unlock it and authorize USB debugging." >&2
  exit 1
}

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/infra-nixCfg/B1
mkdir -p "$state_dir"
snapshot=$(mktemp -d "$state_dir/inspection.XXXXXXXX")

for property in \
  ro.product.manufacturer ro.product.model ro.product.device \
  ro.build.version.release ro.build.version.sdk ro.build.fingerprint \
  ro.product.cpu.abi ro.product.cpu.abilist ro.board.platform \
  ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.slot_suffix; do
  value=$(adb -s "$serial" shell getprop "$property")
  printf '%s=%s\n' "$property" "${value//$'\r'/}" >>"$snapshot/device.txt"
done
adb -s "$serial" shell uname -a >"$snapshot/kernel.txt"
adb -s "$serial" shell cat /proc/version >"$snapshot/kernel-build.txt"
adb -s "$serial" shell wm size >"$snapshot/display.txt"
# Avoid --show-versioncode and cmd role, which older firmware may not support.
adb -s "$serial" shell pm list packages -f >"$snapshot/packages.txt"
adb -s "$serial" shell pm list packages -s >"$snapshot/system-packages.txt"
adb -s "$serial" shell pm list packages -d >"$snapshot/disabled-packages.txt"
adb -s "$serial" shell pm list packages -e >"$snapshot/enabled-packages.txt"
printf 'Read-only snapshot saved to %s\n' "$snapshot"
cat "$snapshot/device.txt"
