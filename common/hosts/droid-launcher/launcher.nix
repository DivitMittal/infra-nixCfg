# Shared by every host running Termux Launcher's Nix edition (com.termux.launcher.nix),
# on top of common/hosts/droid. Pulled in by mkLauncherHost in hosts/droid/enum.nix,
# so it never reaches stock nix-on-droid hosts like M1.
{
  config,
  lib,
  inputs,
  ...
}: let
  toolkit = description: lib.mkEnableOption description;
  # The fork's `launcher` flake template. Its scripts and config files are reused
  # straight from the pinned input instead of being vendored, so they track the
  # fork on `nix flake update nix-on-droid-launcher`.
  launcherTemplate = "${inputs.nix-on-droid-launcher}/templates/launcher";
in {
  # Mirrors the launcher template's toolkits.nix; its `setup-toolkits` script edits
  # ~/.config/nix-on-droid, not this repo, so it isn't wired in here.
  options.launcher.toolkits = {
    shell = toolkit "fish (+ the home/tty fish, starship, fzf and atuin modules), eza, zoxide, yazi, fd, ripgrep";
    eyeCandy = toolkit "fastfetch with the launcher's GIF logo (kitty graphics protocol), timg, chafa";
    editor = toolkit "neovim + :checkhealth deps, and the fork's `setup-nvim` distro chooser (implies build)";
    build = toolkit "a C toolchain and autotools";
    node = toolkit "nodejs";
    go = toolkit "go";
    python = toolkit "python3 and uv";
    # xkeyboard-config is what the display server needs to start; openbox gives
    # windows title bars. Turn the display on in Settings → Display → Linux display.
    gui = toolkit "X11 apps for the launcher's built-in Linux display, listed in the drawer under \"Linux apps\"";
  };

  config = {
    # On top of common/hosts/droid/termux.nix. The fork points these at the
    # launcher's package name, so they reach com.termux.launcher.nix's socket.
    android-integration = {
      termux-wake-lock.enable = true;
      termux-wake-unlock.enable = true;
      # `gx` in neovim and anything else shelling out to xdg-open has no handler
      # inside the proot; this aliases it to termux-open.
      xdg-open.enable = true;
    };

    # `nix search`/`nix run`/`nix shell` and on-device flake switches.
    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';

    # Merges with the shared bridge in common/hosts/droid/home-manager.nix.
    # _home.nix takes the toolkits as a plain argument rather than reading them
    # from its own config: it picks its imports by them, and imports can't
    # depend on the config they produce.
    home-manager.config = {
      imports = [(import ./_home.nix config.launcher.toolkits)];
      _module.args = {inherit launcherTemplate;};
    };
  };
}
