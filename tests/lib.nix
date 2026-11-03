# Unit tests for lib/custom.nix and lib/palette.nix.
{
  lib,
  pkgs,
}: let
  inherit (lib.custom) scanPaths mkUvxBin mkPnpmDlxBin mkZbxBin;
  palette = import ../lib/palette.nix {inherit pkgs;};
  fixture = ./fixtures/scan-paths;

  baseNames = paths: lib.sort lib.lessThan (map baseNameOf paths);
  isHexColor = s: builtins.match "[0-9a-f]{6}" s != null;

  ## Stand-in for pkgs.customDarwin so mkZbxBin can be exercised on any system.
  pkgsWithZerobrew = pkgs // {customDarwin.zerobrew-bin = pkgs.writeTextDir "bin/zbx" "";};
  ## Store-path context must be dropped before regex matching.
  plain = builtins.unsafeDiscardStringContext;
  contains = needle: haystack: lib.hasInfix (plain needle) (plain haystack);
in {
  ## ── scanPaths ──────────────────────────────────────────────────────────────
  testScanPathsSelectsNixFilesAndDirectories = {
    expr = baseNames (scanPaths fixture);
    expected = ["a.nix" "b.nix" "subdir"];
  };

  testScanPathsExcludesOwnDefaultNix = {
    expr = lib.any (p: baseNameOf p == "default.nix") (scanPaths fixture);
    expected = false;
  };

  testScanPathsIgnoresNonNixFiles = {
    expr = lib.any (p: lib.hasSuffix ".md" p || lib.hasSuffix ".bak" p) (map toString (scanPaths fixture));
    expected = false;
  };

  testScanPathsReturnsPathsUnderScannedDir = {
    expr = lib.all (p: lib.hasPrefix (toString fixture + "/") (toString p)) (scanPaths fixture);
    expected = true;
  };

  testScanPathsResultsAreImportable = {
    expr = lib.all (p: builtins.isFunction (import p)) (scanPaths fixture);
    expected = true;
  };

  ## ── mkUvxBin ───────────────────────────────────────────────────────────────
  testMkUvxBinName = {
    expr = (mkUvxBin pkgs "visidata" "visidata").name;
    expected = "visidata";
  };

  testMkUvxBinExecsUvToolRun = {
    expr = contains "${pkgs.uv}/bin/uv tool run --from euporie euporie-preview \"$@\"" (mkUvxBin pkgs "euporie-preview" "--from euporie euporie-preview").text;
    expected = true;
  };

  testMkUvxBinExposesMainProgram = {
    expr = lib.getExe (mkUvxBin pkgs "img2pdf" "img2pdf") == "${mkUvxBin pkgs "img2pdf" "img2pdf"}/bin/img2pdf";
    expected = true;
  };

  ## ── mkPnpmDlxBin ───────────────────────────────────────────────────────────
  testMkPnpmDlxBinName = {
    expr = (mkPnpmDlxBin pkgs "wrangler" "wrangler@latest").name;
    expected = "wrangler";
  };

  testMkPnpmDlxBinExecsPnpmDlx = {
    expr = contains "${pkgs.pnpm}/bin/pnpm dlx wrangler@latest \"$@\"" (mkPnpmDlxBin pkgs "wrangler" "wrangler@latest").text;
    expected = true;
  };

  ## ── mkZbxBin ───────────────────────────────────────────────────────────────
  testMkZbxBinUsesFormulaAsName = {
    expr = (mkZbxBin pkgsWithZerobrew "unxip").name;
    expected = "unxip";
  };

  testMkZbxBinExecsZbx = {
    expr = contains "${pkgsWithZerobrew.customDarwin.zerobrew-bin}/bin/zbx unxip \"$@\"" (mkZbxBin pkgsWithZerobrew "unxip").text;
    expected = true;
  };

  ## ── palette ────────────────────────────────────────────────────────────────
  testPaletteHasAllBase16Slots = {
    expr = lib.attrNames palette.base16Scheme;
    expected = map (i: "base0${i}") (lib.stringToCharacters "0123456789ABCDEF");
  };

  testPaletteColorsAreLowercaseHexWithoutHash = {
    expr = lib.filterAttrs (_: c: !isHexColor c) palette.base16Scheme;
    expected = {};
  };

  testPaletteBackgroundIsPitchBlack = {
    expr = palette.base16Scheme.base00;
    expected = "000000";
  };

  testPaletteOpacitiesAreFractions = {
    expr = lib.filterAttrs (_: o: !(builtins.isFloat o && o >= 0.0 && o <= 1.0)) palette.opacity;
    expected = {};
  };

  testPaletteOpacityCoversStylixTargets = {
    expr = lib.attrNames palette.opacity;
    expected = ["applications" "desktop" "popups" "terminal"];
  };

  testPaletteFontSizesArePositiveInts = {
    expr = lib.filterAttrs (_: s: !(builtins.isInt s && s > 0)) palette.fonts.sizes;
    expected = {};
  };

  testPaletteFontsDeclarePackageAndName = {
    expr = lib.filterAttrs (_: f: !(lib.isDerivation f.package && f.name != "")) (removeAttrs palette.fonts ["sizes"]);
    expected = {};
  };

  testPaletteWallpaperExists = {
    expr = builtins.pathExists palette.wallpaper;
    expected = true;
  };

  testPalettePolarityIsValid = {
    expr = builtins.elem palette.polarity ["dark" "light" "either"];
    expected = true;
  };
}
