# B1: owner-confirmed C69_M_STAR firmware; verify the received unit with b1-device.
{
  imports = [
    ./debloat.nix
    # ./apps.nix # Enable after confirming the ABI, then resolve the app lock.
  ];

  device.name = "B1";
  device.abi = "arm64-v8a";

  apps.cleanup = "none";

  # Replace the frontlight action on this edition, which has no frontlight.
  # b1-device reloads Onyx's mapping after a successful nix-android switch.
  android.settings = {
    global = {
      KEYCODE_BACK = builtins.toJSON {
        keySet = ["KEYCODE_BACK"];
        shortPressAction = "";
        longPressAction = "KEYCODE_APP_SWITCH";
        repeat = false;
      };
      key_custom_side_key_short_press_enable = 0;
    };
    system.screen_off_timeout = 300000;
  };

  # Select individual entries only after comparing the snapshot with catalog.nix.
  # Disabling retains the system APK and its data; removing an entry does NOT
  # re-enable it. See README.md for recovery and firmware compatibility limits.
  boox.disabledPackages = [];
}
