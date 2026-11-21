{
  lib,
  stdenv,
  linuxPackages,
  kernel ? linuxPackages.kernel,
  python3,
}:
stdenv.mkDerivation {
  pname = "hp-bioscfg-m43";
  version = "${kernel.version}-candidate1";
  inherit (kernel) src;
  patches = [./m43.patch];
  nativeBuildInputs = kernel.moduleBuildDependencies ++ [python3];
  hardeningDisable = ["pic"];
  postPatch = ''
    python3 ${./test_patch.py} .
  '';
  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD/drivers/platform/x86/hp/hp-bioscfg" CONFIG_HP_BIOSCFG=m modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm444 drivers/platform/x86/hp/hp-bioscfg/hp-bioscfg.ko \
      $out/lib/modules/${kernel.modDirVersion}/extra/hp-bioscfg.ko
    runHook postInstall
  '';
  meta = {
    description = "Experimental M43 HP BIOS driver with ASCII decoding and padded WMAA input";
    license = lib.licenses.gpl2Only;
    platforms = ["x86_64-linux"];
  };
}
