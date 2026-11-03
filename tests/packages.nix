# Invariants for pkgs/ as exposed through overlays/custom.nix.
# Only metadata is forced; nothing is built or instantiated.
{
  lib,
  pkgs,
}: let
  dirsOf = dir: lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));
  sorted = lib.sort lib.lessThan;

  sets = {
    inherit (pkgs) custom;
    inherit (pkgs) customDarwin;
  };
  allPkgs = lib.concatMapAttrs (set: lib.mapAttrs' (name: lib.nameValuePair "${set}.${name}")) sets;
  failing = pred: lib.attrNames (lib.filterAttrs (_: p: !(pred p)) allPkgs);

  sources = lib.importJSON ../pkgs/_sources/generated.json;
in
  {
    testCustomOverlayExposesEveryPkgsCustomDir = {
      expr = sorted (lib.attrNames pkgs.custom);
      expected = sorted (dirsOf ../pkgs/custom);
    };

    testCustomDarwinOverlayExposesEveryPkgsDarwinDir = {
      expr = sorted (lib.attrNames pkgs.customDarwin);
      expected = sorted (dirsOf ../pkgs/darwin);
    };

    testEveryPkgDirHasPackageNix = {
      expr = lib.filter (d: !(builtins.pathExists (d + "/package.nix"))) (
        map (n: ../pkgs/custom + "/${n}") (dirsOf ../pkgs/custom)
        ++ map (n: ../pkgs/darwin + "/${n}") (dirsOf ../pkgs/darwin)
      );
      expected = [];
    };

    testCustomAndDarwinNamesDoNotCollide = {
      expr = lib.intersectLists (dirsOf ../pkgs/custom) (dirsOf ../pkgs/darwin);
      expected = [];
    };

    testEveryPackageHasDescription = {
      expr = failing (p: (p.meta.description or "") != "");
      expected = [];
    };

    testDescriptionsDoNotEndWithPeriod = {
      expr = failing (p: !(lib.hasSuffix "." (p.meta.description or "")));
      expected = [];
    };

    testEveryPackageHasLicense = {
      expr = failing (p: p.meta ? license);
      expected = [];
    };

    testEveryPackageDeclaresPlatforms = {
      expr = failing (p: (p.meta.platforms or []) != []);
      expected = [];
    };

    testEveryPackageHasVersion = {
      expr = failing (p: (p.version or "") != "");
      expected = [];
    };

    testDarwinPackagesAreDarwinOnly = {
      expr = lib.attrNames (lib.filterAttrs (_: p: lib.any (s: !(lib.hasSuffix "-darwin" (toString s))) p.meta.platforms) pkgs.customDarwin);
      expected = [];
    };

    testNvfetcherSourcesHaveVersions = {
      expr = lib.attrNames (lib.filterAttrs (_: s: (s.version or "") == "") sources);
      expected = [];
    };
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    testInfatOverrideLinksAppKit = {
      expr = pkgs.infat.drvAttrs.NIX_LDFLAGS or null;
      expected = "-framework AppKit";
    };
  }
