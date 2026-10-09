{
  lib,
  stdenvNoCC,
  sources,
  _7zz,
  makeWrapper,
  ...
}: let
  inherit (sources.hyperhdr-aarch64) version;
  platform = stdenvNoCC.hostPlatform.system;
  src =
    {
      aarch64-darwin = sources.hyperhdr-aarch64.src;
      x86_64-darwin = sources.hyperhdr-x86_64.src;
    }.${
      platform
    };
in
  stdenvNoCC.mkDerivation {
    pname = "hyperhdr";
    inherit version src;

    nativeBuildInputs = [_7zz makeWrapper];

    unpackPhase = ''
      runHook preUnpack
      7zz x -snld $src
      runHook postUnpack
    '';

    ## DMG unpacks to HyperHDR-<version>-macOS-<arch>/hyperhdr.app
    sourceRoot = ".";

    dontFixup = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications
      cp -R HyperHDR-*-macOS-*/hyperhdr.app $out/Applications/
      makeWrapper $out/Applications/hyperhdr.app/Contents/MacOS/hyperhdr $out/bin/hyperhdr

      runHook postInstall
    '';

    meta = {
      description = "Open source ambient lighting (Ambilight) with HDR/SDR video capture";
      homepage = "https://github.com/awawa-dev/HyperHDR";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = ["aarch64-darwin" "x86_64-darwin"];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "hyperhdr";
    };
  }
