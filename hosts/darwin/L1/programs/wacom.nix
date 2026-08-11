{pkgs, ...}: {
  environment.systemPackages = [pkgs.customDarwin.wacom-toggle];
}
