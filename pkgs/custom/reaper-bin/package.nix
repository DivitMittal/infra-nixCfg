{
  stdenvNoCC,
  stdenv,
  fetchurl,
  lib,
  makeWrapper,
  _7zz,
  autoPatchelfHook,
  alsa-lib,
  libpulseaudio,
  pipewire,
  ...
}: let
  version = "7.66";
  verShort = builtins.replaceStrings ["."] [""] version;

  sources =
    lib.attrsets.optionalAttrs stdenvNoCC.hostPlatform.isLinux {
      x86_64-linux = {
        url = "https://www.reaper.fm/files/7.x/reaper${verShort}_linux_x86_64.tar.xz";
        hash = "sha256-GMNtVql069snZzvaUrw0SEygbbnafS20HSzLdQDC6yU=";
      };
      i686-linux = {
        url = "https://www.reaper.fm/files/7.x/reaper${verShort}_linux_i686.tar.xz";
        hash = "sha256-eXG7Zds+hFBFMyjovdpLmLNRkxMIfExQw0xcKTuo21Q=";
      };
      aarch64-linux = {
        url = "https://www.reaper.fm/files/7.x/reaper${verShort}_linux_aarch64.tar.xz";
        hash = "sha256-imoVxmC9oPzcl8dDtrs93/ADEB9NQFCThHZlxb8FIac=";
      };
      armv7l-linux = {
        url = "https://www.reaper.fm/files/7.x/reaper${verShort}_linux_armv7l.tar.xz";
        hash = "sha256-vP+pyjgMNovVDFitTlmPpghWRIubWgWfWpADGU28SsY=";
      };
    }
    // lib.attrsets.optionalAttrs stdenvNoCC.hostPlatform.isDarwin {
      x86_64-darwin = {
        url = "https://www.reaper.fm/files/7.x/reaper${verShort}_universal.dmg";
        hash = "sha256-I+nZtcOhzlrX0xLJBxB6DE1ZtYNgMRHuutOW6MVZuMc=";
      };
      aarch64-darwin = {
        url = "https://www.reaper.fm/files/7.x/reaper${verShort}_universal.dmg";
        hash = "sha256-I+nZtcOhzlrX0xLJBxB6DE1ZtYNgMRHuutOW6MVZuMc=";
      };
    };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "Unsupported platform: ${stdenvNoCC.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation (_finalAttrs: {
    pname = "reaper";
    inherit version;

    src = fetchurl {
      inherit (source) url hash;
    };

    nativeBuildInputs =
      lib.optionals stdenvNoCC.hostPlatform.isLinux [autoPatchelfHook makeWrapper]
      ++ lib.optionals stdenvNoCC.hostPlatform.isDarwin [_7zz makeWrapper];

    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
      alsa-lib
      libpulseaudio
      pipewire
      # libstdc++; stdenvNoCC has no compiler, so its .cc is null.
      stdenv.cc.cc.lib
    ];

    unpackPhase =
      if stdenvNoCC.hostPlatform.isLinux
      then ''
        tar -xf $src
      ''
      else ''
        7zz x -snld $src
      '';

    sourceRoot =
      if stdenvNoCC.hostPlatform.isLinux
      then "REAPER"
      else "REAPER_INSTALL_UNIVERSAL/REAPER.app";

    installPhase =
      if stdenvNoCC.hostPlatform.isLinux
      then ''
        runHook preInstall

        mkdir -p $out/opt/REAPER
        cp -r . $out/opt/REAPER/

        mkdir -p $out/bin
        makeWrapper $out/opt/REAPER/reaper $out/bin/reaper

        runHook postInstall
      ''
      else ''
        runHook preInstall

        mkdir -p "$out/Applications/REAPER.app"
        cp -R . "$out/Applications/REAPER.app"

        if [[ -e "$out/Applications/REAPER.app/Contents/MacOS/REAPER" ]]; then
          makeWrapper "$out/Applications/REAPER.app/Contents/MacOS/REAPER" "$out/bin/reaper"
        fi

        runHook postInstall
      '';

    meta = {
      description = "Digital Audio Workstation";
      homepage = "https://www.reaper.fm";
      license = lib.licenses.unfree;
      platforms = builtins.attrNames sources;
      maintainers = with lib.maintainers; [DivitMittal];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "reaper";
    };
  })
