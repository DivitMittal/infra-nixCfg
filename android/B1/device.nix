# B1: owner-confirmed C69_M_STAR firmware; verify the received unit with b1-device.
{
  imports = [
    ./debloat.nix
    ./apps.nix
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

  # B1 is a reader. Disable optional apps and printing, plus diagnostics and
  # NFC that were already disabled on the received unit.
  boox.disabledPackages = [
    "com.android.bips"
    "com.android.egg"
    "com.android.nfc"
    "com.android.printservice.recommendation"
    "com.bia.tt"
    "com.onyx.android.production.test"
    "com.onyx.factorytest"
    "com.onyx.mail"
  ];
}
