# Which package groups _home.nix installs. Edit, then `nix-on-droid switch --flake .#M1N`.
# Mirrors the launcher template's toolkits.nix; its `setup-toolkits` script edits
# ~/.config/nix-on-droid, not this repo, so it isn't wired in here.
{
  # fish (+ your home/tty fish, starship, fzf and atuin modules), eza, zoxide, yazi, fd, ripgrep.
  shell = true;
  # fastfetch with the launcher's GIF logo (kitty graphics protocol), timg, chafa.
  eyeCandy = true;
  # neovim + :checkhealth deps, and the fork's `setup-nvim` distro chooser. Implies `build`.
  editor = true;
  build = true;
  node = false;
  go = false;
  python = false;
  # X11 apps for the launcher's built-in Linux display: they show up in the app
  # drawer under "Linux apps". xkeyboard-config is what the display server needs
  # to start; openbox gives windows title bars. Turn the display on in
  # Settings → Display → Linux display.
  gui = true;
}
