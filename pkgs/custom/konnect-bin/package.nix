{
  lib,
  stdenv,
  autoPatchelfHook,
  sources,
  ...
}: let
  platform = stdenv.hostPlatform.system;
  sourcesByPlatform = {
    aarch64-darwin = sources.konnect-aarch64-darwin;
    x86_64-darwin = sources.konnect-x86_64-darwin;
    x86_64-linux = sources.konnect-x86_64-linux;
  };
  source =
    sourcesByPlatform.${platform}
    or (throw "Unsupported platform: ${platform}");
in
  stdenv.mkDerivation {
    pname = "konnect";
    inherit (source) version;
    inherit (source) src;

    sourceRoot = ".";

    ## Linux release is a glibc-linked PIE; darwin binaries are unsigned but run as-is
    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [stdenv.cc.cc.lib];
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 konnect $out/bin/konnect

      runHook postInstall
    '';

    meta = {
      description = "KiCad 10 MCP server for AI-assisted schematic and PCB design";
      homepage = "https://github.com/mixelpixx/Konnect";
      license = lib.licenses.agpl3Only;
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = builtins.attrNames sourcesByPlatform;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "konnect";
    };
  }
