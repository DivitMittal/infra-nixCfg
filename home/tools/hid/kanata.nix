{
  pkgs,
  inputs,
  hostPlatform,
  ...
}: let
  configFile = inputs.TLTR + "/kanata/tltr.kbd";
in {
  imports = [inputs.kanata-tray.homeManagerModules.kanata-tray];

  home.packages = [
    pkgs.customDarwin.kanata-tray-daemon
    pkgs.kanata-with-cmd
  ];

  programs.kanata-tray = {
    enable = true;
    # The flake builds from its own nixpkgs, which throws on x86_64-darwin (Nixpkgs 26.11+)
    package =
      if hostPlatform.isDarwin && hostPlatform.isx86_64
      then
        pkgs.callPackage (inputs.kanata-tray + "/nix/package.nix") {
          inherit hostPlatform;
          build-deps = [pkgs.pkg-config];
          runtime-deps = [];
          self = inputs.kanata-tray;
        }
      else inputs.kanata-tray.packages.${hostPlatform.system}.kanata-tray;

    settings = {
      general = {
        allow_concurrent_presets = false;
      };
      defaults = {
        kanata_executable = "${pkgs.kanata-with-cmd}/bin/kanata";
        tcp_port = 5830;
      };
      presets = {
        TLTR = {
          kanata_config = "${configFile}";
          autorun = true;
          extra_args = ["--nodelay"];
        };
      };
    };
  };
}
