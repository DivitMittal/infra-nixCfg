# B1: Boox C69 HD, 16 GB, Android 11 per the owner. ABI is not yet inspected.
{
  imports = [
    ./debloat.nix
    # ./apps.nix # Enable after confirming the ABI, then resolve the app lock.
  ];

  device.name = "B1";
  # Provisional, not a hardware finding. The engine rejects a mismatched target.
  # Replace with ro.product.cpu.abi from inspect.sh and update apps.lock.json.
  device.abi = "armeabi-v7a";

  # Keep the initial manifest empty so onboarding cannot remove existing apps.
  apps.cleanup = "none";

  # Select individual entries only after comparing the snapshot with catalog.nix.
  # Disabling retains the system APK and its data; removing an entry does NOT
  # re-enable it. See README.md for recovery and firmware compatibility limits.
  boox.disabledPackages = [];
}
