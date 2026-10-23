{
  lib,
  inputs,
  hostPlatform,
  ...
}: {
  imports = [
    inputs.nixos-apple-silicon.nixosModules.apple-silicon-installer
  ];

  image.fileName = lib.mkForce "nixos-as-${hostPlatform.system}.iso";

  # mkCfg hands NixOS a prebuilt `pkgs`, leaving this option unset; the
  # apple-silicon installer module reads it (and so does flake/iso-packages.nix
  # when it probes every nixosConfiguration for isoImage).
  nixpkgs.hostPlatform = hostPlatform.system;

  # Asahi Linux binary cache — avoids rebuilding the custom kernel during ISO build
  nix.settings = {
    trusted-substituters = [
      "https://nixos-apple-silicon.cachix.org"
    ];
    trusted-public-keys = [
      "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
    ];
  };
}
