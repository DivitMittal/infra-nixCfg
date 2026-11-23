## Windows hosts managed via jacobbrugh/nix-win (see flake/mkWinCfg.nix).
##
## Attribute names MUST be the lowercased Windows computer name — nix-win.ps1
## resolves `winConfigurations.$((hostname).ToLower())` when no -FlakeAttr is
## given. `hostName` passed to mkWinCfg stays capitalized to match the
## hosts/win/<hostName> and common/hosts/win directory layout.
{mkWinCfg, ...}: {
  flake.winConfigurations = {
    l1 = mkWinCfg {
      hostName = "L1";
    };

    l2 = mkWinCfg {
      hostName = "L2";
    };
  };
}
