{lib, ...}: {
  # Shared by `colima` (x86_64, on L1) and `colima-arm` (aarch64, on ASL1).
  # These are the x86 values, as defaults so colima-arm's override in
  # hosts/nixos/enum.nix replaces them instead of conflicting.
  topology.self = {
    hardware.info = lib.mkDefault "NixOS VM - Colima/Lima (x86_64) on L1 (macOS)";

    interfaces = {
      eth0 = {
        network = lib.mkDefault "colima-x86";
        type = "virtual";
        virtual = true;
        physicalConnections = lib.mkDefault [
          {
            node = "L1";
            interface = "col0";
          }
        ];
      };
    };
  };
}
