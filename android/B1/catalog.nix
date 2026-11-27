# Reviewed against RodrickRK/boox-debloat apps.json at
# e045a46d0d694f94814838aac1a33b7e601e7382 (MIT).
# This is a candidate catalog for C69_M_STAR, not a C69 HD compatibility claim.
{
  candidates = {
    "com.android.bips" = "Built-in printing";
    "com.android.calllogbackup" = "Call log backup";
    "com.android.cellbroadcastreceiver" = "Emergency alerts";
    "com.android.cellbroadcastreceiver.module" = "Emergency alerts module";
    "com.android.cellbroadcastservice" = "Emergency alert service";
    "com.android.cts.ctsshim" = "Compatibility test shim";
    "com.android.cts.priv.ctsshim" = "Privileged compatibility test shim";
    "com.android.egg" = "Android Easter egg";
    "com.android.printservice.recommendation" = "Print recommendations";
    "com.android.smspush" = "SMS push";
    "com.bia.tt" = "Education app";
    "com.onyx.android.production.test" = "Production diagnostics";
    "com.onyx.factorytest" = "Factory diagnostics";
    "com.onyx.mail" = "Onyx mail client";
    "com.qualcomm.embms" = "Cellular broadcast";
    "com.qualcomm.qti.dynamicddsservice" = "Dual-SIM data switching";
    "com.qualcomm.qti.sva" = "Voice activation";
    "com.qualcomm.qti.uimGbaApp" = "SIM authentication";
    "com.qualcomm.qti.xrvd.service" = "XR video";
    "vendor.qti.iwlan" = "Wi-Fi calling";
    "com.android.nfc" = "NFC";
  };

  # Preserve sleep-picture selection, media indexing, OTA and Google services.
  protected = [
    "com.onyx"
    "com.onyx.android.ksync"
    "com.onyx.screenmanager"
    "com.simplemobiletools.gallery"
    "com.android.providers.media"
    "com.android.providers.media.module"
    "com.onyx.android.onyxotaservice"
    "com.android.vending"
    "com.google.android.gms"
    "com.google.android.gsf"
  ];
}
