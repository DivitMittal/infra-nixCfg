{
  lib,
  stdenvNoCC,
  sources,
  ...
}: let
  platform = stdenvNoCC.hostPlatform.system;
  # macOS ships one universal binary tarball; Linux is split per-arch.
  sourcesByPlatform = {
    aarch64-darwin = sources.moviebox-tui-darwin;
    x86_64-darwin = sources.moviebox-tui-darwin;
    x86_64-linux = sources.moviebox-tui-x86_64-linux;
    aarch64-linux = sources.moviebox-tui-aarch64-linux;
  };
  source =
    sourcesByPlatform.${platform}
    or (throw "moviebox-tui: no upstream binary for platform ${platform}");
in
  stdenvNoCC.mkDerivation {
    pname = "moviebox-tui";
    inherit (source) version;
    inherit (source) src;

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 moviebox-tui $out/bin/moviebox-tui
      install -Dm644 LICENSE-MIT $out/share/licenses/moviebox-tui/LICENSE-MIT
      install -Dm644 LICENSE-APACHE $out/share/licenses/moviebox-tui/LICENSE-APACHE
      runHook postInstall
    '';

    meta = {
      description = "Modern Rust terminal UI for streaming — fast, lightweight, keyboard-first";
      homepage = "https://github.com/mesamirh/MovieBox-Tui";
      license = with lib.licenses; [mit asl20];
      maintainers = with lib.maintainers; [DivitMittal];
      platforms = builtins.attrNames sourcesByPlatform;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "moviebox-tui";
    };
  }
