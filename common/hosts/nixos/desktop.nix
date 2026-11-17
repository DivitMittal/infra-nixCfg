# NixOS-level desktop integration for the Sway session: login manager, PolicyKit, screen-lock
# PAM, XDG portals, and dconf.
#
# This lives in common/hosts/nixos (applied to every nixos host, including WSL and the ISOs),
# so it is gated to the hosts that actually run the graphical session.
# WSL/M1/colima home configs are tty-only, so a greeter there would be broken.
{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (lib.elem config.hostSpec.hostName ["L2" "T2" "T3" "ASL1N"]) {
  # greetd + agreety (greetd's built-in TUI greeter). Launch Sway through a login shell so the
  # user's nix profile (which provides the home-manager-built sway) is on PATH at exec time.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.bash}/bin/bash -lc sway";
      user = "greeter";
    };
  };

  # GUI privilege prompts (agent runs from the Sway session — see home/gui/linux/sway/sway.nix).
  security.polkit.enable = true;

  # Let swaylock authenticate the user to unlock.
  security.pam.services.swaylock = {};

  # Screen sharing (wlroots backend) + native file pickers (gtk backend).
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };

  # GTK application settings backend.
  programs.dconf.enable = true;
}
