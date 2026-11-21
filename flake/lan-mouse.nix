{lib, ...}: let
  desk = import ../lib/lan-mouse.nix {inherit lib;};
in {
  flake.lanMouse = {
    inherit (desk) peers layout configurations windows;
  };

  perSystem = {pkgs, ...}: {
    packages.lan-mouse-windows = pkgs.linkFarm "lan-mouse-windows" [
      {
        name = "L2.json";
        path = pkgs.writeText "lan-mouse-L2.json" (builtins.toJSON desk.windows.L2);
      }
      {
        name = "Apply.ps1";
        path = ../utils/lan_mouse_windows.ps1;
      }
    ];
  };
}
