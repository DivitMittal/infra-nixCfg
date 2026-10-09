{
  lib,
  stdenvNoCC,
  sources,
  ...
}: let
  platform = stdenvNoCC.hostPlatform.system;
  # Linux releases are static musl binaries — no dynamic linking to patch.
  sourcesByPlatform = {
    aarch64-darwin = sources.diskwatch-aarch64-darwin;
    x86_64-darwin = sources.diskwatch-x86_64-darwin;
    aarch64-linux = sources.diskwatch-aarch64-linux;
    x86_64-linux = sources.diskwatch-x86_64-linux;
  };
  source =
    sourcesByPlatform.${platform}
    or (throw "diskwatch: no upstream binary for platform ${platform}");
  # Tarball root is a single bare binary named after the platform variant.
  binName =
    {
      aarch64-darwin = "diskwatch-macos-aarch64";
      x86_64-darwin = "diskwatch-macos-x86_64";
      aarch64-linux = "diskwatch-linux-aarch64-static";
      x86_64-linux = "diskwatch-linux-x86_64-static";
    }.${
      platform
    };
in
  stdenvNoCC.mkDerivation {
    pname = "diskwatch";
    inherit (source) version;
    inherit (source) src;

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 ${binName} $out/bin/diskwatch
      runHook postInstall
    '';

    meta = {
      description = "Single-host, read-only disk diagnostics TUI — sibling to netwatch and syswatch";
      homepage = "https://github.com/matthart1983/diskwatch";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = builtins.attrNames sourcesByPlatform;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "diskwatch";
    };
  }
