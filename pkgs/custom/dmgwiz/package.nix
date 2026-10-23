{
  lib,
  rustPlatform,
  sources,
  perl,
}:
rustPlatform.buildRustPackage {
  pname = "dmgwiz";
  version = lib.removePrefix "v" sources.dmgwiz.version;

  inherit (sources.dmgwiz) src;

  cargoHash = "sha256-KZH+V6Q/zgtD5/Ket0cLg87Xj7YVwdX/Xik+umAmqAk=";

  nativeBuildInputs = [perl];

  meta = {
    description = "Extract filesystem data from DMG files";
    homepage = "https://github.com/citruz/dmgwiz";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    maintainers = with lib.maintainers; [DivitMittal];
    mainProgram = "dmgwiz";
  };
}
