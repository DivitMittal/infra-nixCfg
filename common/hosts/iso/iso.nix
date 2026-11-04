{
  modulesPath,
  lib,
  ...
}: let
  inherit (lib) mkDefault;
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  isoImage = {
    # mkDefault: the Asahi installer module sets its own level for as-iso.
    squashfsCompression = mkDefault "zstd";
    makeEfiBootable = mkDefault true;
    makeUsbBootable = mkDefault true;
  };

  # Override root password for installation media
  users.users.root.initialPassword = "nixos";
}
