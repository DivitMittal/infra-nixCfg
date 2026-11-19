# Optional bundle for EPUBs, research PDFs, AI web conversations and RSS.
# Import from device.nix after confirming its ABI, then android-rebuild update
# with --lock android/B1/apps.lock.json before building or switching.
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
  ];

  # F-Droid's flavor disables user patches; keep the official package identity.
  apps.release."org.koreader.launcher".url = "https://github.com/koreader/koreader/releases/download/${sources.koreaderVersion}/koreader-android-${architecture}-${sources.koreaderVersion}.apk";
}
