{
  lib,
  inputs,
  hostPlatform,
  pkgs,
  ...
}: let
  inherit (lib) mkForce;
in {
  imports = [
    inputs.nixos-hardware.nixosModules.apple-t2
  ];

  image.fileName = mkForce "nixos-l1n-${hostPlatform.system}.iso";

  nix.settings = {
    trusted-substituters = [
      "https://t2linux.cachix.org"
      "https://cache.soopy.moe"
    ];
    trusted-public-keys = [
      "t2linux.cachix.org-1:P733c5Gt1qTcxsm+Bae0renWnT8OLs0u9+yfaK2Bejw="
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };

  environment.systemPackages = lib.attrsets.attrValues {
    inherit
      (pkgs)
      python3
      dmg2img
      ;
    inherit (pkgs.custom) get-apple-firmware;
  };
}
