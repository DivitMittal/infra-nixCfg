{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    ## Schematic capture & PCB layout. nixpkgs kicad-base is meta.broken on
    ## darwin, so use the cask. brew-nix only knows its `binary` artifacts (with
    ## an unset $APPDIR) and skips the `suite`, so install the KiCad/ folder of
    ## apps ourselves and link the CLIs the cask declares
    kicad =
      if hostPlatform.isDarwin
      then
        pkgs.brewCasks.kicad.overrideAttrs (_: {
          installPhase = ''
            runHook preInstall

            find . -name '*:com.apple.*' -delete
            suite=$(dirname "$(find . -maxdepth 4 -type d -name KiCad.app -print -quit)")
            mkdir -p $out/Applications $out/bin
            cp -R "$suite" $out/Applications/KiCad
            for bin in kicad-cli dxf2idf idf2vrml idfcyl idfrect; do
              ln -s $out/Applications/KiCad/KiCad.app/Contents/MacOS/$bin $out/bin/$bin
            done

            runHook postInstall
          '';
        })
      else pkgs.kicad;

    ## Code-defined circuits (`ato`). nixpkgs atopile depends on kicad-base,
    ## which is meta.broken on darwin; PyPI ships cp314 macOS wheels instead
    atopile =
      if hostPlatform.isDarwin
      then lib.custom.mkUvxBin "ato" "--python 3.14 --from atopile ato"
      else pkgs.atopile;

    ## React/TypeScript circuits (`tsci`); not packaged in nixpkgs
    tscircuit = lib.custom.mkBunxBin "tsci" "tscircuit@latest";
  };
}
