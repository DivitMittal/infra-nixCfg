{mkCfg, ...}: let
  class = "iso";
in {
  flake.nixosConfigurations = {
    iso = mkCfg {
      inherit class;
      hostName = "iso";
      system = "x86_64-linux";
    };
    l1n-iso = mkCfg {
      inherit class;
      hostName = "l1n-iso";
      system = "x86_64-linux";
    };
    # aarch64-linux — requires a native aarch64 builder or binfmt+QEMU to build
    as-iso = mkCfg {
      inherit class;
      hostName = "as-iso";
      system = "aarch64-linux";
    };
  };
}
