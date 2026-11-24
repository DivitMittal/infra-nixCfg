_: {
  perSystem = {pkgs, ...}: {
    # Exposing a package does not build or install it in a home profile.
    packages.zlib-cli = pkgs.custom.zlib-cli;
  };
}
