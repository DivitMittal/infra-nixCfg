{
  self,
  inputs,
  ...
}: {
  flake.homeManagerModules = {
    all = inputs.import-tree (self + "/modules/home");
    default = self.outputs.homeManagerModules.all;

    # Individual modules for selective importing
    discordo = import ./home/discordo.nix;
    glow = import ./home/glow.nix;
    ov = import ./home/ov.nix;
    spotatui = import ./home/spotatui.nix;
    spotifyd = import ./home/spotifyd.nix;
    warpd = import ./home/warpd.nix;
    wiki-tui = import ./home/wiki-tui.nix;
  };

  flake.darwinModules = {
    all = inputs.import-tree (self + "/modules/hosts/darwin");
    default = self.outputs.darwinModules.all;

    # Individual modules for selective importing
    kanata = import ./hosts/darwin/kanata.nix;
    kanata-tray = import ./hosts/darwin/kanata-tray.nix;
    spotifyd = import ./hosts/darwin/spotifyd.nix;
  };

  flake.nixosModules = {
    # Kernel Forge is deliberately NOT part of an `all`/default bundle: it must be
    # attached explicitly per host (proving host first, hardware escalation later).
    kernel-forge = import ./hosts/nixos/kernel-forge.nix;
  };
}
