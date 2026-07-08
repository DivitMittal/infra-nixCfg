{
  inputs,
  mkCfg,
  ...
}: {
  flake.nixosConfigurations = let
    class = "nixos";
  in {
    WSL = mkCfg {
      inherit class;
      hostName = "WSL";
      system = "x86_64-linux";
      additionalModules = [inputs.nixos-wsl.nixosModules.default];
    };
    colima = mkCfg {
      inherit class;
      hostName = "colima";
      system = "x86_64-linux";
    };
    colima-arm = mkCfg {
      inherit class;
      hostName = "colima";
      system = "aarch64-linux";
      additionalModules = [
        {
          # Override topology for the ARM variant: runs on AS-darwin, not L1
          topology.self = {
            hardware.info = "NixOS VM - Colima/Lima (aarch64) on ASL1 (Apple Silicon macOS)";
            interfaces.eth0 = {
              network = "colima-arm";
              physicalConnections = [
                {
                  node = "ASL1";
                  interface = "col0";
                }
              ];
            };
          };
        }
      ];
    };
    L2 = mkCfg {
      inherit class;
      hostName = "L2";
      system = "x86_64-linux";
    };
    T2 = mkCfg {
      inherit class;
      hostName = "T2";
      system = "x86_64-linux";
    };
    ASL1N = mkCfg {
      inherit class;
      hostName = "ASL1N";
      system = "aarch64-linux";
    };
    KFORGE = mkCfg {
      inherit class;
      hostName = "KFORGE";
      system = "x86_64-linux";
      # Proving host for the Kernel Forge track; profile appended last so it
      # deliberately overrides host defaults. Never attached to a deploy node.
      additionalModules = [./profiles/kernel-forge-extreme.nix];
    };
    VPS1 = mkCfg {
      inherit class;
      hostName = "VPS1";
      system = "x86_64-linux";
      # First NixOS host to consume system-level agenix secrets (root/div password hashes)
      additionalModules = [inputs.agenix.nixosModules.default];
    };
    VPS2 = mkCfg {
      inherit class;
      hostName = "VPS2";
      system = "x86_64-linux";
      additionalModules = [inputs.agenix.nixosModules.default];
    };
  };
}
