{
  stdenvNoCC,
  lib,
  sources,
  _7zz,
  ...
}:
stdenvNoCC.mkDerivation (_finalAttrs: {
  pname = "BattOpt";
  inherit (sources.BattOpt) version src;

  nativeBuildInputs = [_7zz];

  # 7zz writes HFS xattrs out as `file:com.apple.*` siblings, which break the
  # bundle's sealed resources
  unpackPhase = ''
    7zz x -snld $src
    find . -name '*:com.apple.*' -delete
  '';

  sourceRoot = "BattOpt Installer/BattOpt.app";

  # Notarized universal binaries; fixup would invalidate the signature
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications/BattOpt.app" "$out/bin"
    cp -R . "$out/Applications/BattOpt.app"

    # The CLI ships inside the bundle; the app normally copies it to
    # /Library/Application Support/battopt and adds /etc/paths.d/battopt
    ln -s "$out/Applications/BattOpt.app/Contents/Resources/battopt" "$out/bin/battopt"

    runHook postInstall
  '';

  meta = {
    description = "Hybrid GUI/CLI battery charge limiter for macOS";
    homepage = "https://github.com/js4jiang5/BattOpt";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    maintainers = with lib.maintainers; [DivitMittal];
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    mainProgram = "battopt";
  };
})
