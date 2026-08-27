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
    # nixpkgs' vicinae has had no binary cache on x86_64-darwin since NixOS
    # 26.11 dropped that system; build from vicinae's own bundled flake
    # (backed by vicinae.cachix.org) there instead, nixpkgs everywhere else.
    vicinae =
      if super.stdenv.hostPlatform.system == "x86_64-darwin"
      then inputs.vicinae.packages.x86_64-darwin.default
      else super.vicinae;
  };
}
