# Syncs TTY dotfiles managed by home-manager to the Windows XDG paths via /mnt/c/.
# Auto-imported for all homeConfigurations via import-tree ./tty; the mkIf guard
# makes it a strict no-op on every host except WSL.
#
# What is synced (and why not the rest):
#   git/attributes  ✓  cross-platform, no OS-specific paths
#   git/ignore      ✓  cross-platform
#   git/config      ✗  has Linux-specific sslCAInfo; Ansible template handles Windows correctly
#   starship.toml   ✓  identical format on all platforms
#   fastfetch       ✓  logo-free variant (Nix store path invalid on Windows)
#   Profile.ps1     ✗  Windows-only, no Linux equivalent
#   whkdrc          ✗  Windows window manager, no Linux equivalent
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf optionalString;
  winHome = "/mnt/c/Users/${config.home.username}";
  winConfig = "${winHome}/.config";
in
  mkIf (config.hostSpec.hostName == "WSL") (let
    # Fastfetch config stripped of the iTerm logo (Nix store path invalid on Windows).
    # Inherits display settings and modules from the home-manager-managed config.
    fastfetchWin = pkgs.writeText "fastfetch-windows.jsonc" (builtins.toJSON {
      display = config.programs.fastfetch.settings.display;
      modules = config.programs.fastfetch.settings.modules;
    });
  in {
    # ── Windows dotfile sync activation ─────────────────────────────────────────
    # Runs after writeBoundary so all Linux-side sources exist in the Nix store.
    # $DRY_RUN_CMD is set to `echo` by home-manager in --dry-run mode.
    home.activation.syncWindowsDotfiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _sync_log() { echo "[wsl→windows] $*" >&2; }

      # Only run when the Windows drive is actually mounted (not in CI / nix build)
      if [[ ! -d "${winHome}" ]]; then
        _sync_log "Windows home not found at ${winHome} — skipping"
        return 0
      fi

      _sync_log "Syncing to ${winConfig}"

      ${optionalString config.programs.git.enable ''
        $DRY_RUN_CMD mkdir -p "${winConfig}/git"
        ${optionalString (config.programs.git.attributes != []) ''
          $DRY_RUN_CMD cp --remove-destination \
            "${config.xdg.configFile."git/attributes".source}" \
            "${winConfig}/git/attributes"
        ''}
        ${optionalString (config.programs.git.ignores != []) ''
          $DRY_RUN_CMD cp --remove-destination \
            "${config.xdg.configFile."git/ignore".source}" \
            "${winConfig}/git/ignore"
        ''}
        _sync_log "git/attributes + git/ignore ✓"
      ''}

      ${optionalString config.programs.starship.enable ''
        $DRY_RUN_CMD mkdir -p "${winConfig}"
        $DRY_RUN_CMD cp --remove-destination \
          "${config.xdg.configFile."starship.toml".source}" \
          "${winConfig}/starship.toml"
        _sync_log "starship.toml ✓"
      ''}

      ${optionalString config.programs.fastfetch.enable ''
        $DRY_RUN_CMD mkdir -p "${winConfig}/fastfetch"
        $DRY_RUN_CMD cp --remove-destination \
          "${fastfetchWin}" \
          "${winConfig}/fastfetch/config.jsonc"
        _sync_log "fastfetch/config.jsonc ✓ (logo stripped)"
      ''}

      _sync_log "Done"
    '';
  })
