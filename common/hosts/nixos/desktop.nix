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
lib.mkIf (lib.elem config.hostSpec.hostName ["L2" "L1N" "T2" "ASL1N"]) {
  # greetd + agreety (greetd's built-in TUI greeter). Launch Sway through a login shell so the
  # user's nix profile (which provides the home-manager-built sway) is on PATH at exec time.
  services.greetd = {
    enable = true;
    # agreety asks for the login, then runs Sway as that user. Running
    # `bash -lc sway` here directly ran it as `greeter`, which has no sway, so
    # greetd restart-looped into start-limit-hit (seen on T2's first boot).
    settings.default_session = {
      command = "${config.services.greetd.package}/bin/agreety --cmd ${lib.escapeShellArg "${pkgs.bash}/bin/bash -lc sway"}";
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
