{
  self,
  inputs,
  ...
}: {
  # https://github.com/areofyl/fetch — ships its own home-manager module
  # (nix/home-module.nix) rather than one living in nixpkgs; nixpkgs' own
  # `pkgs.fetch` is pinned to v2.1.0, which predates macOS support and
  # custom-logo.txt handling entirely, so pull the flake input directly.
  imports = [inputs.areofyl-fetch.homeManagerModules.default];

  programs.fetch = {
    enable = true;

    info = [
      "os"
      "kernel"
      "terminal"
      "cpu"
      "gpu"
      "memory"
      "swap"
      "ip"
    ];

    labelColor = "magenta";
    separator = "-";
    light = "top-left";
    spin = "xy";
    speed = 1.0;
    size = 1.0;

    # depth/logo_outer/logo_inner aren't yet typed options upstream (see
    # nix/home-module.nix's maintenance checklist) — pass them raw.
    extraConfig = ''
      depth=2.0
      logo_outer=magenta
      logo_inner=white
    '';
  };

  # ASCII rendition of assets/qezta.png (fastfetch's logo), generated via:
  #   chafa --size 45x24 --symbols ascii --colors 16 --color-space rgb \
  #     --format symbols --fg-only -O 0 assets/qezta.png
  xdg.configFile."fetch/logo.txt".source = self + "/assets/qezta-fetch-logo.txt";
}
