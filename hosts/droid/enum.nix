{
  inputs,
  mkCfg,
  ...
}: {
  flake.nixOnDroidConfigurations = let
    class = "droid";
    # Termux Launcher, Nix edition (com.termux.launcher.nix): built against the
    # launcher's nix-on-droid fork, plus the layer every launcher host shares.
    mkLauncherHost = hostName:
      mkCfg {
        inherit class hostName;
        system = "aarch64-linux";
        nixOnDroidSource = inputs.nix-on-droid-launcher;
        additionalModules = [(inputs.import-tree ../../common/hosts/droid-launcher)];
      };
  in {
    M1 = mkCfg {
      inherit class;
      hostName = "M1";
      system = "aarch64-linux";
    };
    # Installs side by side with M1's stock Termux on the same phone.
    M1N = mkLauncherHost "M1N";
  };
}
