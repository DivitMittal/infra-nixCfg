# nix-android device module for the M1 phone (same physical device as the
# nix-on-droid host at hosts/droid/M1/M1.nix — this manages Android/adb-level
# state instead of the Termux/proot environment). See docs/OPTIONS.md at
# github:devindudeman/nix-android for the full option surface.
{
  device.name = "M1";
  # Read from the phone (DN2103, Android 16) on 2026-11-19.
  device.abi = "arm64-v8a";

  apps.fdroid.packages = [
    "org.fdroid.fdroid"
  ];
  # The Nix environment is Termux Launcher's Nix edition
  # (com.termux.launcher.nix, from PickleHik3/termux-launcher's `-nix`
  # releases), configured by hosts/droid/M1 (#70). Stock com.termux is not used.

  # First Obtainium-tracked app to migrate off Obtainium itself — nix-android's
  # own bench config uses this exact source as its worked example.
  # The installed build is the GitHub one (dev.imranr.obtainium), not the
  # F-Droid flavour.
  apps.release."dev.imranr.obtainium".github = "ImranR98/Obtainium";
}
