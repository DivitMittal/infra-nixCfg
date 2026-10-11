{
  lib,
  stdenvNoCC,
  fetchurl,
}:
# Prebuilt Mesa with Turnip (Adreno Vulkan) + Zink (GL-on-Vulkan) for Termux.
#
# Source: a Termux-compatible prebuilt Mesa tarball. There is no canonical
# upstream release; pick one and pin it here.
#
#   * Termux's `mesa` deb (extract first, then point `url` at the tarball)
#   * A community prebuild (GrenderG/Mesa-Turnip-Builder,
#     frlan/mesa-turnip-android, …)
#
# To fill in: run `nix-prefetch-url --unpack <url>` and replace the
# `lib.fakeSha256` placeholder. Until then, building with
# `programs.termux-gui.gpu.enable = true` will fail at fetch time with a
# clear hash-mismatch error. The X11-only path (gpu.enable = false) is
# unaffected.
stdenvNoCC.mkDerivation rec {
  pname = "mesa-turnip";
  version = "0.0.0-unpinned";

  src = fetchurl {
    # TODO: replace with a real release URL.
    url = "https://example.invalid/${pname}-${version}-aarch64.tar.zst";
    sha256 = lib.fakeSha256;
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"

    # Layout varies: accept either a Termux-deb-style `usr/lib/...` extract
    # or a flat tarball with .so files at the root.
    if [ -d usr/lib ]; then
      cd usr/lib
    fi

    # Adreno Vulkan ICD (Turnip)
    find . -name 'libvulkan_freedreno.so*' -exec cp -P {} "$out/lib/" \;

    # DRI drivers (Zink, kmsro, swrast, …)
    if [ -d dri ]; then
      mkdir -p "$out/lib/dri"
      cp -P dri/* "$out/lib/dri/"
    fi

    # GL / EGL / GLES libs (Zink's libGL shim, etc.)
    find . \( -name 'libGL.so*' -o -name 'libEGL.so*' -o -name 'libGLES*.so*' \) \
      -exec cp -P {} "$out/lib/" \;

    runHook postInstall
  '';

  meta = {
    description = "Prebuilt Mesa with Turnip (Adreno Vulkan) + Zink (GL-on-Vulkan) for Termux";
    homepage = "https://github.com/termux/termux-packages";
    license = lib.licenses.mit;
    platforms = ["aarch64-linux"];
  };
}
