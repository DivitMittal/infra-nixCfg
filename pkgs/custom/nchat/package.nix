{
  lib,
  stdenvNoCC,
  sources,
  ...
}: let
  platform = stdenvNoCC.hostPlatform.system;
  # Upstream nchat has no x86_64-darwin release — only macos-arm64 + linux glibc.
  sourcesByPlatform = {
    aarch64-darwin = sources.nchat-aarch64-darwin;
    aarch64-linux = sources.nchat-aarch64-linux;
    x86_64-linux = sources.nchat-x86_64-linux;
  };
  source =
    sourcesByPlatform.${platform}
    or (throw "nchat: no upstream binary for platform ${platform}");
in
  stdenvNoCC.mkDerivation {
    pname = "nchat";
    inherit (source) version;
    inherit (source) src;

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      # Tarball root is versioned: nchat-<ver>-<plat>/{bin,share,...}
      cd nchat-*
      install -Dm755 bin/nchat $out/bin/nchat
      install -Dm644 share/man/man1/nchat.1 $out/share/man/man1/nchat.1
      install -Dm644 share/doc/nchat/LICENSE $out/share/doc/nchat/LICENSE
      install -Dm644 LICENSE $out/share/licenses/nchat/LICENSE
      runHook postInstall
    '';

    meta = {
      description = "Terminal client for Telegram with multiple accounts support";
      homepage = "https://github.com/d99kris/nchat";
      license = lib.licenses.gpl3Only;
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = builtins.attrNames sourcesByPlatform;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "nchat";
    };
  }
