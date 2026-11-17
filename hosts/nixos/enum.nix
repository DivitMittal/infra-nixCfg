{
  inputs,
  mkCfg,
  ...
}: {
  flake.nixosConfigurations = let
    class = "nixos";
    homelabT640 = [./_homelab/base.nix ./_homelab/t640.nix];
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
          # Override topology for the ARM variant: runs on AS-darwin, not L1.
          # Same hostName as `colima`, so it needs its own node id or the
          # two VMs collapse into one conflicting node.
          topology.id = "colima-arm";
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
    # ── home lab (hosts/README.md, "Home-lab bootstrap") ─────────────────
    # T1 router, T3 GUI/AI, T4 services: HP t640s. MON1: Lenovo S100.
    T1 = mkCfg {
      inherit class;
      hostName = "T1";
      system = "x86_64-linux";
      additionalModules = homelabT640;
    };
    T3 = mkCfg {
      inherit class;
      hostName = "T3";
      system = "x86_64-linux";
      additionalModules = homelabT640 ++ [./_homelab/agents.nix];
    };
    T4 = mkCfg {
      inherit class;
      hostName = "T4";
      system = "x86_64-linux";
      additionalModules = homelabT640 ++ [./_homelab/agents.nix];
    };
    MON1 = mkCfg {
      inherit class;
      hostName = "MON1";
      system = "x86_64-linux";
      additionalModules = [./_homelab/base.nix];
    };
    ASL1N = mkCfg {
      inherit class;
      hostName = "ASL1N";
      system = "aarch64-linux";
    };
    VPS0 = mkCfg {
      inherit class;
      hostName = "VPS0";
      system = "aarch64-linux";
      # VPS Home Manager profiles deploy separately through deploy-rs `*-home` nodes.
      additionalModules = [inputs.agenix.nixosModules.default];
    };
    VPS1 = mkCfg {
      inherit class;
      hostName = "VPS1";
      system = "x86_64-linux";
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
