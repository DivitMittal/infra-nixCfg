{
  lib,
  stdenvNoCC,
  sources,
  ...
}: let
  platform = stdenvNoCC.hostPlatform.system;
  sourcesByPlatform = {
    aarch64-darwin = sources.simplex-chat-cli-aarch64-darwin;
    x86_64-darwin = sources.simplex-chat-cli-x86_64-darwin;
    aarch64-linux = sources.simplex-chat-cli-aarch64-linux;
    x86_64-linux = sources.simplex-chat-cli-x86_64-linux;
  };
  source =
    sourcesByPlatform.${platform}
    or (throw "Unsupported platform: ${platform}");
in
  stdenvNoCC.mkDerivation {
    pname = "simplex-chat-cli";
    inherit (source) version;
    inherit (source) src;

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/simplex-chat
      runHook postInstall
    '';

    meta = {
      description = "Terminal CLI for SimpleX Chat — private messaging without user IDs";
      homepage = "https://simplex.chat";
      license = lib.licenses.agpl3Only;
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = builtins.attrNames sourcesByPlatform;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "simplex-chat";
    };
  }
