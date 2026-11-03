{inputs}: {
  # Custom overlay that provides additional packages from local directories
  #
  # Performance note: packagesFromDirectoryRecursive is efficient as it:
  # 1. Lazily evaluates packages (only builds what's actually used)
  # 2. Uses Nix's evaluation cache for directory structure scans
  # 3. Properly handles dependencies between packages
  #
  # The packages are organized by platform/type:
  # - customDarwin: macOS-specific packages
  # - custom: General custom packages for all platforms
  custom = self: super: let
    sources = super.callPackage ../pkgs/_sources/generated.nix {};
  in {
    customDarwin = super.lib.packagesFromDirectoryRecursive {
      callPackage = super.lib.customisation.callPackageWith (self // {inherit sources;});
      directory = ../pkgs/darwin;
    };
    custom = super.lib.packagesFromDirectoryRecursive {
      callPackage = super.lib.customisation.callPackageWith (self // {inherit sources;});
      directory = ../pkgs/custom;
    };
    # nixpkgs infat misses AppKit linkage — NSWorkspace is AppKit, not Foundation.
    # Upstream fix: add `env.NIX_LDFLAGS = "-framework AppKit"` to pkgs/by-name/in/infat/package.nix
    infat = super.infat.overrideAttrs (old: {
      env =
        (old.env or {})
        // super.lib.optionalAttrs super.stdenv.hostPlatform.isDarwin {
          NIX_LDFLAGS = toString [
            "-framework"
            "AppKit"
          ];
        };
    });
    # nixpkgs' vicinae is Linux-only (meta.platforms has no darwin).
    # aarch64-darwin: vicinae's own flake package (cached at vicinae.cachix.org).
    # x86_64-darwin: vicinae's pinned nixpkgs has dropped that system and throws,
    # so build its derivation (via its overlay) against our 26.05-darwin pkgs.
    # Linux: nixpkgs.
    vicinae =
      if super.stdenv.hostPlatform.system == "x86_64-darwin"
      then (inputs.vicinae.overlays.default self super).vicinae
      else if super.stdenv.hostPlatform.isDarwin
      then inputs.vicinae.packages.${super.stdenv.hostPlatform.system}.default
      else super.vicinae;
  };
}
