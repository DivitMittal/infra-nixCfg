{
  inputs,
  lib,
  withSystem,
  self,
  ...
}: let
  mkCfg = {
    hostName,
    class,
    system,
    additionalModules ? [],
    extraSpecialArgs ? {},
  }:
    withSystem system (ctx: let
      configGenerator = rec {
        nixos = lib.nixosSystem;
        darwin = inputs.nix-darwin.lib.darwinSystem;
        droid = inputs.nix-on-droid.lib.nixOnDroidConfiguration;
        home = inputs.home-manager.lib.homeManagerConfiguration;
        iso = nixos;
        netboot = nixos;
      };
      inherit (ctx.pkgs.stdenvNoCC) hostPlatform;
      inherit (lib.attrsets) optionalAttrs mergeAttrsList;
      pkgs = ctx.pkgs.extend (
        self: super:
          mergeAttrsList [
            {
              master = inputs.nixpkgs-master.legacyPackages.${hostPlatform.system};
              stable = inputs."nixpkgs-2605".legacyPackages.${hostPlatform.system};
            }
            # (optionalAttrs hostPlatform.isDarwin {
            #   darwinStable = inputs.nixpkgs-darwin.legacyPackages.${hostPlatform.system};
            # })
            (
              optionalAttrs (class == "home") (mergeAttrsList [
                (inputs.nur.overlays.default self super)
                (optionalAttrs hostPlatform.isDarwin (inputs.brew-nix.overlays.default self super))
              ])
            )
            (optionalAttrs (class == "droid") (inputs.nix-on-droid.overlays.default self super))
          ]
      );
      # Re-extend lib with pkgs now available, partially applying it into the helpers
      # so call sites don't need to pass pkgs explicitly.
      lib' = lib.extend (_: prev: {
        custom =
          prev.custom
          // {
            mkZbxBin = prev.custom.mkZbxBin pkgs;
            mkUvxBin = prev.custom.mkUvxBin pkgs;
            mkPnpmDlxBin = prev.custom.mkPnpmDlxBin pkgs;
          };
      });
      palette = import (self + "/lib/palette.nix") {inherit pkgs;};
      specialArgs =
        {
          inherit self inputs hostPlatform;
          inherit (palette) base16Scheme;
        }
        // extraSpecialArgs;
      modules = let
        commonDir = self + "/common";
        inherit (lib.lists) optionals;
      in
        [{hostSpec = {inherit hostName;};}]
        ++ optionals (class != "droid") [(inputs.import-tree (commonDir + "/all"))]
        ++ optionals (class == "droid") [(commonDir + "/all/hostSpec.nix")]
        ++ optionals (class != "home" && class != "droid") [(inputs.import-tree (commonDir + "/hosts/all"))]
        ++ optionals (class == "home") [
          (inputs.import-tree (commonDir + "/home"))
          self.outputs.homeManagerModules.default
        ]
        ++ optionals (class != "home") [
          (inputs.import-tree (commonDir + "/hosts/${class}"))
          (inputs.import-tree (self + "/hosts/${class}/${hostName}"))
        ]
        ++ optionals (class == "iso") [(inputs.import-tree (commonDir + "/hosts/nixos"))]
        ++ optionals (class == "nixos" || class == "iso") [
          inputs.nix-topology.nixosModules.default
        ]
        ++ optionals (class == "nixos") [
          inputs.disko.nixosModules.disko
        ]
        ++ optionals (class == "darwin") [self.outputs.darwinModules.default]
        ++ additionalModules;
    in
      configGenerator.${class} (mergeAttrsList [
        {inherit pkgs modules;}
        (optionalAttrs (class != "droid" && class != "home") {inherit specialArgs;})
        (optionalAttrs (class != "droid") {lib = lib';})
        (
          optionalAttrs (class == "home") {
            extraSpecialArgs = specialArgs;
          }
        )
        (
          optionalAttrs (class == "droid") {
            extraSpecialArgs = specialArgs // {lib = lib';};
          }
        )
      ]));
in {
  _module.args = {
    inherit mkCfg;
  };
}
