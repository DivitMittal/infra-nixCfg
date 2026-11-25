# Build the portfolio's static mirror from a pinned source and lockfile.
{
  pkgs,
  src,
}:
pkgs.stdenv.mkDerivation {
  pname = "divit-ipfs";
  version = "0.0.2";
  inherit src;

  nativeBuildInputs = [pkgs.bun pkgs.nodejs];

  bunDeps = import ./_bun-site-deps.nix {
    inherit pkgs src;
    pname = "divit-ipfs";
    lockfile = ./_divit-ipfs.bun.lock;
    hashes = {
      x86_64-linux = "sha256-k0CKfdWzvdtVqeTwe7wrVbq0tqiB6/BBBLhdO3x8kJQ=";
      x86_64-darwin = "sha256-dG7PgHOSYB6G037h7qjdo8f/fVbnKqWgGhbK5zPRBso=";
    };
  };

  buildPhase = ''
    runHook preBuild
    cp -R "$bunDeps" node_modules
    chmod -R u+w node_modules
    bun run build:ipfs
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
