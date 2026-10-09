{mkCfg, ...}: {
  flake.systemConfigs = let
    class = "system-manager";
  in {
    Linux1 = mkCfg {
      inherit class;
      hostName = "Linux1";
      system = "x86_64-linux";
    };

    VPS3 = mkCfg {
      inherit class;
      hostName = "VPS3";
      system = "x86_64-linux";
    };
  };
}
