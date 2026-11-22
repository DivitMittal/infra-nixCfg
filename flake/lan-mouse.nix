{lib, ...}: let
  desk = import ../lib/lan-mouse.nix {inherit lib;};
in {
  # Exposed for inspection; L2's Windows boot applies its part through nix-win
  # (hosts/win/L2/lan-mouse.nix).
  flake.lanMouse = {
    inherit (desk) peers layout configurations windows;
  };
}
