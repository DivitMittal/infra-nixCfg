{
  stdenvNoCC,
  lib,
  sources,
  unzip,
  ...
}:
stdenvNoCC.mkDerivation (_finalAttrs: {
  pname = "menubar-dock";
  version = lib.removePrefix "v" sources.menubar-dock.version;
  inherit (sources.menubar-dock) src;

  nativeBuildInputs = [unzip];

  sourceRoot = "Menu Bar Dock.app";

  ## Upstream release is a universal, Developer ID-signed & notarized .app;
  ## leave it untouched so the signature stays valid
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications/Menu Bar Dock.app"
    cp -R . "$out/Applications/Menu Bar Dock.app"

    runHook postInstall
  '';

  meta = {
    description = "macOS dock of running/pinned apps in the menu bar";
    homepage = "https://github.com/EthanSK/Menu-Bar-Dock";
    ## No license in the upstream repo
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    maintainers = with lib.maintainers; [DivitMittal];
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
  };
})
