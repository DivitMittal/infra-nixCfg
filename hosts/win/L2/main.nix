## L2 — Windows boot slot on the dual-boot machine (user: vanee).
## Ported from playbooks-4-windows' hosts/L2/{main,packages}.yml.
##
## No win.files dotfiles are declared here: home/vanee/ in
## playbooks-4-windows was still empty at migration time (wezterm/tridactyl/
## whkd were disabled there too, and no vanee-specific fastfetch config
## existed despite the Ansible task having no feature gate — a pre-existing
## gap, not something this migration introduced). Add files under ./files/
## and wire them into win.files here once vanee's dotfiles exist.
{inputs, ...}: {
  win.user.name = "vanee";

  # vanee's Windows-side apps, from what was installed on 2026-11-19. CLI
  # toolchains that were also installed here (node, bun, uv, rust,
  # ripgrep, lazygit, yazi, croc, ouch, ffmpeg, claude-code, codex) are
  # declared in WSL instead: hosts/nixos/L2W. Not declared, and left as is:
  # apm and warp (purpose unclear), openssh (held), firefox and
  # epic-games-launcher (their scoop installs had failed).
  win.scoop.buckets = {
    nonportable = "https://github.com/ScoopInstaller/Nonportable";
    games = "https://github.com/ScoopInstaller/Games";
  };
  win.scoop.packages = {
    # Shell and terminal integration
    clink.bucket = "main";
    atuin.bucket = "main";
    zoxide.bucket = "main";
    neovim.bucket = "main"; # git's core.editor on Windows
    gh.bucket = "main"; # Windows-side git auth
    winfetch.bucket = "main";

    # Desktop tools
    autohotkey.bucket = "extras";
    espanso.bucket = "main";
    powertoys.bucket = "extras";
    windhawk.bucket = "extras";
    lively.bucket = "extras";
    trafficmonitor.bucket = "extras";
    files-np.bucket = "nonportable";
    hwinfo.bucket = "extras";

    # Apps
    kicad.bucket = "extras";
    zoom.bucket = "extras";
    steam.bucket = "games";

    # Networking and sync
    tailscale.bucket = "extras";
    syncthing.bucket = "main";
  };

  windot = {
    gitFullName = inputs.infra-nixCfg-secrets.user.userFullName;
    gitEmail = inputs.infra-nixCfg-secrets.user.email.dev;
    gitSigningKey = null;

    isLaptop = true;
  };

  # Lets `ssh L1` reach L1 (hosts/darwin/L1/services/ssh.nix) as div. Only
  # the alias is declarative — nix-win can't deploy the matching private key
  # without committing it to the store (never do that; see .config/git/ignore
  # in common/hosts/win/dotfiles.nix). Seed it once with
  # utils/provision_l2_ssh_key.sh, run from a box that already holds the
  # shared homelab identity (L1, T2, T3, ...).
  win.files.".ssh/config".text = ''
    Host L1
      HostName 192.168.2.4
      User div
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '';
}
