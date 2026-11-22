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
    # The phone (DN2103). Stock nix-on-droid was retired for the launcher.
    M1 = mkLauncherHost "M1";
  };
}
