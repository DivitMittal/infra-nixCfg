#!/usr/bin/env bash
# Collect what a home-lab host's config needs before its first install:
# the nixos-facter report, disks, and which NIC is which (onboard vs USB).
#
# Run it on the target while it's booted into any NixOS installer (USB ISO
# or t1-netboot), from the workstation:
#
#   ssh root@<target-ip> 'bash -s' < utils/collect_hw.sh > <host>-hw.txt
#   ssh root@<target-ip> cat /tmp/facter.json > hosts/nixos/<host>/facter.json
#
# Read-only: it never writes to the disks.
set -euo pipefail

echo "== facter =="
if ! command -v nixos-facter >/dev/null; then
  nix --extra-experimental-features 'nix-command flakes' \
    run nixpkgs#nixos-facter -- -o /tmp/facter.json >&2
else
  nixos-facter -o /tmp/facter.json >&2
fi
echo "report written to /tmp/facter.json ($(wc -c </tmp/facter.json) bytes)"

echo
echo "== disks =="
lsblk -d -o NAME,SIZE,MODEL,TRAN,TYPE

echo
echo "== network interfaces (bus tells onboard from USB) =="
for dev in /sys/class/net/*; do
  name="$(basename "$dev")"
  [ "$name" = lo ] && continue
  [ -e "$dev/device" ] || continue
  path="$(readlink -f "$dev/device")"
  case "$path" in
  */usb*) bus=usb ;;
  *) bus=pci ;;
  esac
  driver="$(basename "$(readlink -f "$dev/device/driver")")"
  printf '%-16s bus=%-4s driver=%-12s mac=%s carrier=%s\n' \
    "$name" "$bus" "$driver" "$(cat "$dev/address")" "$(cat "$dev/carrier" 2>/dev/null || echo ?)"
done

echo
echo "== cpu / memory =="
grep -m1 'model name' /proc/cpuinfo
grep MemTotal /proc/meminfo

echo
echo "== firmware =="
if [ -d /sys/firmware/efi ]; then echo UEFI; else echo "legacy BIOS"; fi
