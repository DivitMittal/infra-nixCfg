# Declarative gaming stack, primarily for Rocket League (Steam Play / Proton).
# Host-scoped to L2 only (this dir is auto-imported for L2 alone via mkCfg,
# see flake/mkCfg.nix) — T2/ASL1N don't get this.
{pkgs, ...}: {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = [pkgs.proton-ge-bin];
    # Manages a protontricks install wired to Steam's Proton prefixes — needed
    # to point BakkesMod at Rocket League's compatdata prefix.
    protontricks.enable = true;
  };

  programs.gamemode.enable = true;

  # Bluetooth Xbox controller support (xpadneo is more reliable than the
  # generic xpad driver for wireless pairing/rumble).
  hardware.xpadneo.enable = true;

  environment.systemPackages = with pkgs; [
    lutris
    heroic
    winetricks
    gamescope
  ];
}
