## Builder for Windows hosts (L1/L2's Windows boot slot), managed via
## jacobbrugh/nix-win rather than the shared mkCfg dispatch in ./mkCfg.nix.
##
## Why not another branch of mkCfg's configGenerator: nix-win's `winSystem`
## is a plain `{ modules ? []; specialArgs ? {}; pkgs ? null }: ...` lambda
## with no `...` in its argument pattern — it errors on any extra attribute.
## mkCfg unconditionally merges in `{ lib = lib'; }` for every class except
## "droid", which would break winSystem's call. Keeping this separate avoids
## threading a "win" special-case through logic that every other host class
## (nixos/darwin/droid/home) also depends on.
##
## Directory conventions mirror mkCfg: common/hosts/win/ (shared Windows
## config) + hosts/win/<hostName>/ (per-host), both pulled in via import-tree.
{
  inputs,
  withSystem,
  self,
  ...
}: let
  mkWinCfg = {
    hostName,
    system ? "x86_64-linux",
    additionalModules ? [],
    extraSpecialArgs ? {},
  }:
    withSystem system (ctx: let
      inherit (ctx.pkgs.stdenvNoCC) hostPlatform;
      commonDir = self + "/common";
      specialArgs =
        {
          inherit self inputs hostPlatform;
        }
        // extraSpecialArgs;
    in
      inputs.nix-win.lib.winSystem {
        inherit (ctx) pkgs;
        inherit specialArgs;
        modules =
          [
            (inputs.import-tree (commonDir + "/hosts/win"))
            (inputs.import-tree (self + "/hosts/win/${hostName}"))
          ]
          ++ additionalModules;
      });
in {
  _module.args = {
    inherit mkWinCfg;
  };
}
