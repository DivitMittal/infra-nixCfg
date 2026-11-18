{mkCfg, ...}: let
  class = "netboot";
in {
  flake.nixosConfigurations = {
    # PXE/TFTP netboot image for T1 (HP t640 thin client): used to run
    # nixos-facter for hardware detection and as the nixos-anywhere install
    # source. Build system.build.netbootRamdisk / .kernel / .netbootIpxeScript
    # and serve them from the TFTP/PXE server.
    t1-netboot = mkCfg {
      inherit class;
      hostName = "t1-netboot";
      system = "x86_64-linux";
    };
  };
}
