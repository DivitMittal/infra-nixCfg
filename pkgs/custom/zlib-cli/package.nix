{
  lib,
  stdenvNoCC,
  fetchurl,
}: let
  version = "0.0.16";
  releases = {
    x86_64-darwin = {
      platform = "darwin_x86_64";
      hash = "sha256-78s17fvs7CiLJ77oWoZc0VXABZqv0/4UUV9uuW4MktQ=";
    };
    aarch64-darwin = {
      platform = "darwin_arm64";
      hash = "sha256-PdjtOl+wSD8kpS6siTrpN3wW2/qeEPmz0BMDDvQ4V9g=";
    };
    x86_64-linux = {
      platform = "linux_x86_64";
      hash = "sha256-qckepELy/lhBSjLtKkV7T3vtRpyQadiA5gRz+l4zj1g=";
    };
    aarch64-linux = {
      platform = "linux_arm64";
      hash = "sha256-5XhMQbxh9kxLlnrSEWisSZd5MJazaAHPGUm5qe2SNFM=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system};
in
  stdenvNoCC.mkDerivation {
    pname = "zlib-cli";
    inherit version;
    src = fetchurl {
      url = "https://github.com/heartleo/zlib/releases/download/v${version}/zlib_${version}_${release.platform}.tar.gz";
      inherit (release) hash;
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 zlib "$out/bin/zlib"
      runHook postInstall
    '';
    meta = {
      description = "A command-line tool for Z-Library";
      homepage = "https://github.com/heartleo/zlib";
      license = lib.licenses.mit;
      platforms = builtins.attrNames releases;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "zlib";
    };
  }
