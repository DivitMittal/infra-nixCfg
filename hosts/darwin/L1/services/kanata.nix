{
  pkgs,
  inputs,
  hostPlatform,
  ...
}: {
  services.kanata = {
    enable = false;
    package = pkgs.kanata-with-cmd;
  };

  services.kanata-tray = {
    enable = false;
    # The flake builds from its own nixpkgs, which throws on x86_64-darwin (Nixpkgs 26.11+)
    package = pkgs.callPackage (inputs.kanata-tray + "/nix/package.nix") {
      inherit hostPlatform;
      build-deps = [pkgs.pkg-config];
      runtime-deps = [];
      self = inputs.kanata-tray;
    };
    environment = {
      KANATA_RSCROLL = "1";
    };
  };
}
