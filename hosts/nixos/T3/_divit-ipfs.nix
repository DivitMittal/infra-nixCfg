# Build the portfolio's static mirror from a pinned source and lockfile.
{
  pkgs,
  src,
}:
pkgs.stdenv.mkDerivation {
  pname = "divit-ipfs";
  version = "0.0.2";
  inherit src;

  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.pnpmConfigHook
    pkgs.pnpm
  ];

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit src;
    pname = "divit-ipfs";
    version = "0.0.2";
    inherit (pkgs) pnpm;
    fetcherVersion = 3;
    hash = "sha256-u/pYln38HEV17lAWvEj6vXlmalzWKKc8QdElYCrZfus=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm run build:ipfs
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    test -f build/ipfs/index.html
    test -d build/ipfs/_app
    test -f build/ipfs/pp_ascii.svg
    test ! -e build/ipfs/api
    mkdir -p "$out"
    cp -a build/ipfs/. "$out/"
    runHook postInstall
  '';
}
