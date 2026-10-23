_: {
  flake.openwrtConfigurations = {
    R1 = import ./R1;
    # OpenWrt/ImmortalWrt guest VM running on T1 (hosts/nixos/T1/router-vm.nix)
    # — not to be confused with the T1 NixOS host itself. See
    # flake/openwrt-t640.nix for the nuci deploy wiring.
    T640 = import ./T640;
  };
}
