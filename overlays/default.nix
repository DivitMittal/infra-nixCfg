{inputs, ...}: let
  # Import custom overlays once and reuse
  # This is evaluated once per Nix evaluation and cached
  custom-overlays = import ./custom.nix {};
in {
  flake.overlays = {
    # Named overlays for selective use
    inherit (custom-overlays) custom;

    # Default overlay includes all custom packages
    # Consumers can choose to use specific overlays or the default
    default = custom-overlays.custom;

    # brew-nix casks built against the consuming pkgs. brew-nix's own overlay
    # uses its nixpkgs input, which throws on x86_64-darwin (Nixpkgs 26.11+).
    brewCasks = final: _: {
      brewCasks = import (inputs.brew-nix + "/casks.nix") {
        pkgs = final;
        inherit (inputs) brew-api;
      };
    };
  };
}
