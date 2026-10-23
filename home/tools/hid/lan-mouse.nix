{
  inputs,
  lib,
  hostPlatform,
  pkgs,
  ...
}: {
  imports = [inputs.lan-mouse.homeManagerModules.default];

  home.packages = [
    pkgs.custom.uniclipboard-cli-bin
  ];

  programs.lan-mouse = {
    enable = true;
    # The flake builds from its own nixpkgs, which throws on x86_64-darwin (Nixpkgs 26.11+)
    package =
      (
        if hostPlatform.isDarwin && hostPlatform.isx86_64
        then pkgs.lan-mouse
        else inputs.lan-mouse.packages.${hostPlatform.system}.default
      ).overrideAttrs (_: {
        buildInputs = [];
        cargoBuildFlags = ["--no-default-features"];
        cargoTestFlags = ["--no-default-features"];
      });
    systemd = true;
    launchd = true;
    settings = {
      port = 4242;
      release_bind = ["KeyLeftCtrl" "KeyLeftShift" "KeyEsc"];
      clients = [
        {
          position = "top";
          ips = ["192.168.77.2"];
          port = 4242;
        }
      ];
    };
  };

  # Service defined but not auto-started — start manually via systemctl/launchctl
  systemd.user.services.lan-mouse.Install.WantedBy = lib.mkForce [];
  launchd.agents.lan-mouse.config.RunAtLoad = lib.mkForce false;
}
