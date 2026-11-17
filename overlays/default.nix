{inputs, ...}: let
  # Import custom overlays once and reuse
  # This is evaluated once per Nix evaluation and cached
  custom-overlays = import ./custom.nix {inherit inputs;};
in {
  flake.overlays = {
    # Named overlays for selective use
    inherit (custom-overlays) custom;

    # Default overlay includes all custom packages
    # Consumers can choose to use specific overlays or the default
    default = custom-overlays.custom;
  };
}
