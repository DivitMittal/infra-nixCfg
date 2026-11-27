# Reading apps and on-device APK sources for B1.
{config, ...}: let
  sources = builtins.fromJSON (builtins.readFile ./koreader/sources.json);
  architecture =
    if config.device.abi == "arm64-v8a"
    then "arm64"
    else if config.device.abi == "armeabi-v7a"
    then "arm"
    else throw "B1 KOReader: confirm an ARM device ABI before resolving APKs";
in {
  apps.fdroid.packages = [
    "info.plateaukao.einkbro"
    "com.nononsenseapps.feeder"
    # Replaces Onyx's ~70 MB LatinIME; TLTR layout applied via b1-keyboard.
    "juloo.keyboard2"
  ];

  # Use Aurora's upstream signing channel for compatibility with Obtainium updates.
  apps.release."com.aurora.store".url = "https://gitlab.com/api/v4/projects/6922885/uploads/245eec8867a47057cbc54535f73b32ee/AuroraStore-4.8.4.apk";
  apps.release."dev.imranr.obtainium".url = "https://github.com/ImranR98/Obtainium/releases/download/v1.7.5/app-arm64-v8a-release.apk";

  apps.release."app.inkos".url = "https://github.com/gezimos/inkOS/releases/download/v0.6/app.inkos_v0.6-Signed.apk";

  # Aurora delivers Play apps through its on-device installer.
  apps.attended = ["com.openai.chatgpt"];

  # F-Droid's flavor disables user patches; keep the official package identity.
  apps.release."org.koreader.launcher".url = "https://github.com/koreader/koreader/releases/download/${sources.koreaderVersion}/koreader-android-${architecture}-${sources.koreaderVersion}.apk";
}
