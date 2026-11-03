# nix-android device module for the M1 phone (same physical device as the
# nix-on-droid host at hosts/droid/M1/M1.nix — this manages Android/adb-level
# state instead of the Termux/proot environment). See docs/OPTIONS.md at
# github:devindudeman/nix-android for the full option surface.
{
  device.name = "M1";
  # Placeholder — confirm with `adb shell getprop ro.product.cpu.abi` against
  # the real phone, then re-run `android-rebuild update` if it differs.
  device.abi = "arm64-v8a";

  apps.fdroid.packages = [
    "org.fdroid.fdroid"
    "com.termux" # already managed on-device per hosts/droid/M1/M1.nix's termux-gui usage
  ];

  # First Obtainium-tracked app to migrate off Obtainium itself — nix-android's
  # own bench config uses this exact source as its worked example.
  apps.release."dev.imranr.obtainium.fdroid".github = "ImranR98/Obtainium";
}
