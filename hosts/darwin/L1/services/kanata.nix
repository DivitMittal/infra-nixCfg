{
  pkgs,
  inputs,
  hostPlatform,
  ...
}: {
  services.kanata = {
    enable = false;
    package = pkgs.kanata-with-cmd;
  };

  services.kanata-tray = {
    enable = false;
    package = inputs.kanata-tray.packages.${hostPlatform.system}.kanata-tray;
  };
}
