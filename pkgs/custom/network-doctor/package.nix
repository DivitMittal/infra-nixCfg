{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule {
  pname = "network-doctor";
  version = "1.10.5";

  src = fetchFromGitHub {
    owner = "heymaikol";
    repo = "network-doctor";
    rev = "v1.10.5";
    hash = "sha256-nyKK/vS0+290sf33yl03FFWbwWdyMi0PCfIzc5pJdXo=";
  };

  vendorHash = "sha256-Lsq6iF0s1IyyMC2d7Eej/FxHo7wGLxB8q1RbaQrQmkw=";

  meta = {
    description = "Cross-platform network troubleshooting TUI";
    homepage = "https://github.com/heymaikol/network-doctor";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [DivitMittal];
    platforms = lib.platforms.unix;
    mainProgram = "netdoc";
  };
}
