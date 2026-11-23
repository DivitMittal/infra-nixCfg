#!/usr/bin/env bash
# Device-free test of E1's nix-android profile against a fake adb that answers
# like the real Echo Show 5: Android 7.1.2 (SDK 25), armeabi-v7a, no `cmd role`
# / `cmd uimode` / `cmd locale` services, and a `pm` that predates
# `--show-versioncode`. Any shell command the fake doesn't know fails the run,
# so an engine upgrade that starts probing a post-7.1 primitive for E1 shows up
# here instead of on the device.
#
# usage: sdk25-check.sh BASH CONVERGE_E1 CONVERGE_PROBE
#   CONVERGE_E1    — the converge wrapper built from android/E1/device.nix
#   CONVERGE_PROBE — the same profile plus the SDK 25-safe primitives
#                    (raw settings, packages.disabled)
set -euo pipefail

bash_bin=${1:?usage: sdk25-check.sh BASH CONVERGE_E1 CONVERGE_PROBE}
converge_e1=${2:?}
converge_probe=${3:?}

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export T=$tmp LOG=$tmp/adb.log XDG_STATE_HOME=$tmp/state
export NIX_ANDROID_ADB=$tmp/adb

fail() {
  echo "sdk25-check: $1" >&2
  sed 's/^/  adb: /' "$LOG" >&2 || true
  exit 1
}

printf '#!%s\n' "$bash_bin" >"$NIX_ANDROID_ADB"
cat >>"$NIX_ANDROID_ADB" <<'EOF'
set -euo pipefail
[ "$1" = -s ] && shift 2
[ "$1" = shell ] || { echo "UNHANDLED adb $*" >>"$LOG"; exit 99; }
cmd=$(printf '%s' "$2" | tr -d "'")
echo "$cmd" >>"$LOG"
case $cmd in
"getprop ro.product.cpu.abi") cat "$T/abi" ;;
"getprop ro.build.fingerprint") echo "Amazon/cronos/cronos:7.1.2/fake:user/release-keys" ;;
"getprop ro.build.version.incremental") echo fake ;;
"pm list packages --show-versioncode"*) echo "Error: Unknown option: --show-versioncode" ;;
"pm list packages --user 0") printf 'package:android\npackage:com.amazon.example.bloat\n' ;;
"pm list packages -3 --user 0") echo package:com.amazon.example.bloat ;;
"pm list packages -d --user 0") ;;
"pm list packages --user 0 com.amazon.example.bloat") echo package:com.amazon.example.bloat ;;
"settings get --user 0 global stay_on_while_plugged_in") echo 0 ;;
"settings put --user 0 "* | "pm disable-user --user 0 "*) echo "WRITE $cmd" >>"$LOG" ;;
"dumpsys window policy") echo "    showing=false" ;;
"cmd "*) echo "Can't find service: ${cmd#cmd }" >&2; exit 255 ;;
*) echo "UNHANDLED $cmd" >>"$LOG"; exit 98 ;;
esac
EOF
chmod +x "$NIX_ANDROID_ADB"

run() { # $1 = converge wrapper, rest = flags; echoes exit status
  local status=0
  "$@" --serial E1FAKE >"$tmp/out" 2>&1 || status=$?
  ! grep -q UNHANDLED "$LOG" || fail "engine used a primitive the SDK 25 fake doesn't know"
  echo "$status"
}

## Empty profile: plan is clean and touches nothing but the ABI.
echo armeabi-v7a >"$T/abi"
: >"$LOG"
[ "$(run "$converge_e1")" = 0 ] || fail "E1 plan reported drift on an empty profile"
grep -q 'device matches manifest' "$tmp/out" || fail "E1 plan did not report a match"
[ "$(cat "$LOG")" = "getprop ro.product.cpu.abi" ] || fail "E1 plan made unexpected device reads"

## Switch records a generation without writing anything.
: >"$LOG"
[ "$(run "$converge_e1" --apply --record)" = 0 ] || fail "E1 switch failed"
! grep -q WRITE "$LOG" || fail "E1 switch wrote to the device"
[ -f "$XDG_STATE_HOME/nix-android/E1/generations/1.json" ] || fail "E1 switch recorded no generation"

## ABI guard: a 64-bit device is refused before any other read.
echo arm64-v8a >"$T/abi"
: >"$LOG"
[ "$(run "$converge_e1")" = 2 ] || fail "E1 plan accepted a non-armeabi-v7a device"

## SDK 25-safe primitives plan and apply through the legacy pm path.
echo armeabi-v7a >"$T/abi"
: >"$LOG"
[ "$(run "$converge_probe")" = 3 ] || fail "probe plan did not report pending changes"
: >"$LOG"
[ "$(run "$converge_probe" --apply)" = 0 ] || fail "probe switch failed"
grep -qx 'WRITE settings put --user 0 global stay_on_while_plugged_in 3' "$LOG" || fail "settings write missing"
grep -qx 'WRITE pm disable-user --user 0 com.amazon.example.bloat' "$LOG" || fail "disable write missing"

echo "sdk25-check: ok"
