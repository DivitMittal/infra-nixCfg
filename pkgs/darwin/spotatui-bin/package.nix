{
  lib,
  stdenvNoCC,
  sources,
  cctools,
  darwin,
  portaudio,
  ...
}: let
  inherit (sources.spotatui-aarch64) version;
  platform = stdenvNoCC.hostPlatform.system;
  src =
    {
      aarch64-darwin = sources.spotatui-aarch64.src;
      x86_64-darwin = sources.spotatui-x86_64.src;
    }.${
      platform
    };
in
  stdenvNoCC.mkDerivation {
    pname = "spotatui";
    inherit version src;
    sourceRoot = ".";

    nativeBuildInputs =
      [cctools]
      ++ lib.optional stdenvNoCC.hostPlatform.isAarch64 darwin.autoSignDarwinBinariesHook;

    dontFixup = !stdenvNoCC.hostPlatform.isAarch64;

    # Upstream links Homebrew's portaudio (/usr/local/opt or /opt/homebrew)
    installPhase = ''
      runHook preInstall
      install -Dm755 spotatui $out/bin/spotatui
      old=$(otool -L $out/bin/spotatui | awk '/libportaudio/ {print $1}')
      install_name_tool -change "$old" ${portaudio}/lib/libportaudio.2.dylib $out/bin/spotatui
      runHook postInstall
    '';

    meta = {
      description = "Fully standalone Spotify client for the terminal";
      homepage = "https://github.com/LargeModGames/spotatui";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = ["aarch64-darwin" "x86_64-darwin"];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "spotatui";
    };
  }
