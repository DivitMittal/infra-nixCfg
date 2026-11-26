# Upstream himalaya v2 release binary. nixpkgs-2605 (the last set evaluating on
# x86_64-darwin) still ships v1.2.0, whose config schema no longer matches the
# v2 TOML home-manager's programs.himalaya module now generates.
{
  lib,
  stdenvNoCC,
  fetchurl,
  ...
}: let
  version = "2.2.1";
  hashes = {
    aarch64-darwin = "sha256-pdl6H3u8pF5Yvd3j+fFzJfYUyc1tXxf6vzjdywMIaas=";
    x86_64-darwin = "sha256-JOImvGvM/q3IlgiVP/wPy0ZiPR1M1GiXNMus4kPMjS4=";
  };
  platform = stdenvNoCC.hostPlatform.system;
in
  stdenvNoCC.mkDerivation {
    pname = "himalaya";
    inherit version;

    src = fetchurl {
      url = "https://github.com/pimalaya/himalaya/releases/download/v${version}/himalaya.${platform}.tgz";
      hash = hashes.${platform};
    };
    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 himalaya $out/bin/himalaya
      mkdir -p $out/share
      cp -r share/man $out/share/
      runHook postInstall
    '';

    meta = {
      description = "CLI to manage emails";
      homepage = "https://github.com/pimalaya/himalaya";
      license = lib.licenses.mit;
      platforms = builtins.attrNames hashes;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "himalaya";
    };
  }
