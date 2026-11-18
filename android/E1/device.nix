# nix-android profile for E1, an Amazon Echo Show 5 (product "cronos").
# Managed over adb from T3, which it is plugged into by USB.
#
# The device is 32-bit (armv7l kernel, armeabi-v7a userland) on Android 7.1.2
# (SDK 25). nix-android is tested on SDK 35-37, and on SDK 25:
#   - `android-rebuild import` fails: it queries `cmd role`, which Android only
#     added in 10 (SDK 29). Snapshot/import is unavailable here.
#   - roles (default browser/home/...) can't be declared, for the same reason.
# Only declare state whose primitive exists on 7.1, and check each addition
# with a `plan` before `switch`.
{
  device.name = "E1";
  device.abi = "armeabi-v7a";
}
