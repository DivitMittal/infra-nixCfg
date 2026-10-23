{
  lib,
  rustPlatform,
  sources,
  pkg-config,
  cmake,
  openssl,
  dbus,
  fontconfig,
  makeBinaryWrapper,
  installShellFiles,
  writableTmpDirAsHomeHook,
  # Feature flags (custom defaults)
  withStreaming ? true,
  withDaemon ? true,
  withImage ? true,
  withFuzzy ? true,
  withNotify ? false,
  withSixel ? false,
  withMediaControl ? false,
  withAudioBackend ? "rodio",
  ...
}:
rustPlatform.buildRustPackage {
  pname = "spotify-player";
  version = lib.removePrefix "v" sources.spotify-player.version;

  inherit (sources.spotify-player) src;

  cargoHash = "sha256-RsUuPkX4oVG6mDM16mM7VGW22mvKZPjShqs8BO36hbY=";

  nativeBuildInputs = [
    pkg-config
    cmake
    rustPlatform.bindgenHook
    installShellFiles
    writableTmpDirAsHomeHook
    makeBinaryWrapper
  ];

  buildInputs = [
    openssl
    dbus
    fontconfig
  ];

  buildNoDefaultFeatures = true;

  buildFeatures =
    lib.optional withStreaming "streaming"
    ++ lib.optional withDaemon "daemon"
    ++ lib.optional withImage "image"
    ++ lib.optional withFuzzy "fzf"
    ++ lib.optional withNotify "notify"
    ++ lib.optional withSixel "sixel"
    ++ lib.optional withMediaControl "media-control"
    ++ lib.optional (withAudioBackend == "rodio") "rodio-backend"
    ++ lib.optional (withAudioBackend == "pulseaudio") "pulseaudio-backend"
    ++ lib.optional (withAudioBackend == "alsa") "alsa-backend";

  doCheck = false;

  meta = {
    description = "Terminal spotify player that has feature parity with the official client";
    homepage = "https://github.com/aome510/spotify-player";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [DivitMittal];
    mainProgram = "spotify_player";
  };
}
