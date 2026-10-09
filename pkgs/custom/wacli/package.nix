{
  lib,
  stdenvNoCC,
  sources,
  ...
}: let
  platform = stdenvNoCC.hostPlatform.system;
  sourcesByPlatform = {
    aarch64-darwin = sources.wacli-aarch64-darwin;
    x86_64-darwin = sources.wacli-x86_64-darwin;
    aarch64-linux = sources.wacli-aarch64-linux;
    x86_64-linux = sources.wacli-x86_64-linux;
  };
  source =
    sourcesByPlatform.${platform}
    or (throw "Unsupported platform: ${platform}");
in
  stdenvNoCC.mkDerivation {
    pname = "wacli";
    inherit (source) version;
    inherit (source) src;

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 wacli $out/bin/wacli
      install -Dm644 LICENSE $out/share/licenses/wacli/LICENSE
      runHook postInstall
    '';

    meta = {
      description = "CLI for WhatsApp Web — multi-account, headless, scripting-friendly";
      homepage = "https://github.com/openclaw/wacli";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = builtins.attrNames sourcesByPlatform;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "wacli";
    };
  }
