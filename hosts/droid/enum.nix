{
  inputs,
  mkCfg,
  ...
}: {
  flake.nixOnDroidConfigurations = let
    class = "droid";
  in {
    M1 = mkCfg {
      inherit class;
      hostName = "M1";
      system = "aarch64-linux";
    };
    # Termux Launcher, Nix edition (com.termux.launcher.nix) — installs side by
    # side with M1's stock Termux, built against the launcher's nix-on-droid fork.
    M1N = mkCfg {
      inherit class;
      hostName = "M1N";
      system = "aarch64-linux";
      nixOnDroidSource = inputs.nix-on-droid-launcher;
    };
  };
}
