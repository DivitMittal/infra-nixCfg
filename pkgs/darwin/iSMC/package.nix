{
  lib,
  stdenvNoCC,
  sources,
}:
stdenvNoCC.mkDerivation {
  pname = "iSMC";
  inherit (sources.iSMC) version src;

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 iSMC $out/bin/iSMC
    install -Dm644 LICENSE $out/share/licenses/iSMC/LICENSE
    runHook postInstall
  '';

  meta = {
    description = "Apple SMC CLI — decode temperature, fans, battery, power, voltage and current on macOS";
    homepage = "https://github.com/dkorunic/iSMC";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [DivitMittal];
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    mainProgram = "iSMC";
  };
}
