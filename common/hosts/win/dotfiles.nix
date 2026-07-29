## Dotfiles shared across Windows hosts.
## Ported from playbooks-4-windows' home/common/*.j2 (Jinja2 → Nix string
## interpolation) and roles/dotfiles/tasks/configs.yml.
##
## Per-host identity/feature toggles live under `windot.*` — a small local
## options namespace, kept separate from nix-win's own `win.*` — set by each
## hosts/win/<hostName>/main.nix.
{
  config,
  lib,
  ...
}: let
  cfg = config.windot;
  home = config.win.user.homeDirectory;
  configHome = "${home}\\.config";
in {
  options.windot = {
    gitFullName = lib.mkOption {
      type = lib.types.str;
      description = "git user.name for this Windows account.";
    };
    gitEmail = lib.mkOption {
      type = lib.types.str;
      description = "git user.email for this Windows account.";
    };
    gitSigningKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "git user.signingkey — null disables commit signing.";
    };
    isLaptop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to show the Starship battery module.";
    };
    featureMsys2 = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    featureStarship = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    featureFirefox = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = {
    win.files = {
      # ── Git ─────────────────────────────────────────────────────────────
      ".config/git/config".text = ''
        # Managed by nix-win — do not edit by hand.

        [core]
        	editor        = nvim
        	excludesfile  = ${configHome}/git/ignore
        	autocrlf      = false
        	eol           = lf
        	symlinks      = true

        [credential]
        	selected = manager

        [status]
        	showUntrackedFiles = no

        [safe]
        	directory = *

        [user]
        	name  = ${cfg.gitFullName}
        	email = ${cfg.gitEmail}
        ${lib.optionalString (cfg.gitSigningKey != null) ''
          	signingkey = ${cfg.gitSigningKey}

          [commit]
          	gpgsign = true
        ''}

        [help]
        	autocorrect = 1

        [init]
        	defaultBranch = main

        [push]
        	autoSetupRemote = true

        [pull]
        	rebase = true

        [rebase]
        	autoStash = true

        [diff]
        	colorMoved = zebra

        [merge]
        	conflictstyle = zdiff3

        [alias]
        	graph    = log --oneline --graph --decorate --all
        	last     = log -1 HEAD
        	unstage  = restore --staged
        	clean-U  = clean -d -x -f

        [color]
        	ui = auto
      '';

      ".config/git/attributes".text = ''
        # Git attributes — enforces LF line endings for all text files
        * text=auto eol=lf

        # Force binary treatment for common binary types
        *.png  binary
        *.jpg  binary
        *.jpeg binary
        *.gif  binary
        *.ico  binary
        *.pdf  binary
        *.zip  binary
        *.gz   binary
        *.ttf  binary
        *.woff binary
        *.woff2 binary
      '';

      ".config/git/ignore".text = ''
        # Global gitignore

        # ── OS ────────────────────────────────────────────────────────────
        .DS_Store
        .DS_Store?
        ._*
        .Spotlight-V100
        .Trashes
        desktop.ini
        Thumbs.db
        ehthumbs.db
        $RECYCLE.BIN/

        # ── Editors ───────────────────────────────────────────────────────
        *.swp
        *.swo
        *~
        .idea/
        .vscode/
        *.suo
        *.user
        .vs/

        # ── Build / Runtime ───────────────────────────────────────────────
        __pycache__/
        *.pyc
        *.pyo
        node_modules/
        .direnv/
        result
        result-*

        # ── Secrets ───────────────────────────────────────────────────────
        .env
        .env.*
        *.pem
        *.key
        !*.pub
      '';
    };

    # ── PowerShell profile ─────────────────────────────────────────────────
    # Uses nix-win's dedicated module, which writes to the path pwsh 7
    # actually auto-loads (Documents/PowerShell/Microsoft.PowerShell_profile.ps1).
    # The Ansible version wrote to Documents/PowerShell/Profile.ps1, which pwsh
    # does not auto-source — this is a fix, not just a port.
    win.powershell.profile = ''
      # Managed by nix-win — do not edit by hand.

      # ── Environment Variables ──────────────────────────────────────────────
      # Duplicates the Machine-scope values from ../settings.nix so this shell
      # sees them immediately, without waiting for a new logon/process.
      $env:EDITOR         = "vim"
      $env:VISUAL         = "vim"
      $env:SHELL          = "pwsh"
      $env:XDG_CONFIG_HOME = "${configHome}"
      $env:XDG_DATA_HOME   = "${home}\.local\share"
      $env:XDG_CACHE_HOME  = "${home}\.cache"
      $env:STARSHIP_CONFIG = "${configHome}\starship.toml"
      $env:GIT_CONFIG_GLOBAL = "${configHome}\git\config"

      # ── Aliases — Package Management ───────────────────────────────────────
      function scoop-ultimate {
          Write-Host "[scoop] Updating Scoop..." -ForegroundColor Cyan
          scoop update
          Write-Host "[scoop] Updating all packages..." -ForegroundColor Cyan
          scoop update --all
          Write-Host "[scoop] Cleaning old versions..." -ForegroundColor Cyan
          scoop cleanup --all
          Write-Host "[scoop] Clearing cache..." -ForegroundColor Cyan
          scoop cache rm *
          Write-Host "[scoop] Done." -ForegroundColor Green
      }

      function winget-ultimate {
          Write-Host "[winget] Updating sources..." -ForegroundColor Cyan
          winget source update
          Write-Host "[winget] Upgrading all packages..." -ForegroundColor Cyan
          winget upgrade --all --accept-source-agreements --accept-package-agreements --silent
          Write-Host "[winget] Done." -ForegroundColor Green
      }

      function store-ultimate {
          Write-Host "[store] Applying Microsoft Store updates..." -ForegroundColor Cyan
          store updates --apply
          Write-Host "[store] Done." -ForegroundColor Green
      }

      function windows-ultimate {
          scoop-ultimate
          winget-ultimate
          store-ultimate
          windows-backup
      }

      function windows-backup {
          $backupDir = "${home}\.local\state\windows-backup"
          if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory $backupDir | Out-Null }
          Write-Host "[backup] Saving Scoop list..." -ForegroundColor Cyan
          scoop list > "$backupDir\scoop_backup.txt"
          Write-Host "[backup] Saving Winget list..." -ForegroundColor Cyan
          winget list > "$backupDir\winget_backup.txt"
          Write-Host "[backup] Saved to $backupDir" -ForegroundColor Green
      }

      ${lib.optionalString cfg.featureMsys2 ''
        # ── MSYS2 ─────────────────────────────────────────────────────────────
        function msys {
            & "${home}\scoop\apps\msys2\current\msys2_shell.cmd" -shell fish @args
        }
      ''}

      # ── Shell Initialisation ────────────────────────────────────────────────
      if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
          fastfetch
      }

      ${lib.optionalString cfg.featureStarship ''
        if (Get-Command starship -ErrorAction SilentlyContinue) {
            Invoke-Expression (&starship init powershell)
        }
      ''}
    '';

    win.files."Documents/powershell.config.json".text = builtins.toJSON {
      "Microsoft.PowerShell:ExecutionPolicy" = "RemoteSigned";
    };

    # ── Starship prompt ─────────────────────────────────────────────────────
    win.files.".config/starship.toml" = lib.mkIf cfg.featureStarship {
      text = ''
        format = """
        [╭─](bold blue)\
        $username\
        $hostname\
        $directory\
        $git_branch\
        $git_status\
        $nix_shell\
        $direnv\
        ${lib.optionalString cfg.featureMsys2 "$shell\\"}

        [╰─](bold blue)$character"""

        right_format = """
        $cmd_duration\
        ${lib.optionalString cfg.isLaptop "$battery\\"}
        $nodejs\
        $python\
        $rust\
        $golang\
        $java\
        $terraform\
        $time"""

        [character]
        success_symbol = "[❯](bold green)"
        error_symbol   = "[❯](bold red)"

        [username]
        show_always = true
        format      = "[$user]($style) "
        style_user  = "bold yellow"
        style_root  = "bold red"

        [hostname]
        ssh_only = false
        format   = "[@$hostname]($style) "
        style    = "bold blue"

        [directory]
        truncation_length    = 4
        truncate_to_repo     = true
        format               = "[$path]($style)[$read_only]($read_only_style) "
        style                = "bold cyan"

        [git_branch]
        format = "[$symbol$branch(:$remote_branch)]($style) "
        symbol = " "
        style  = "bold purple"

        [git_status]
        format      = "([$all_status$ahead_behind]($style) )"
        style       = "bold yellow"
        modified    = "📝"
        staged      = "🎤"
        stashed     = "📦"
        untracked   = "?"
        deleted     = "✘"
        renamed     = "»"
        conflicted  = "⚡"
        ahead       = "⇡''${count}"
        behind      = "⇣''${count}"
        diverged    = "⇕⇡''${ahead_count}⇣''${behind_count}"

        [cmd_duration]
        min_time   = 2_000
        format     = "[$duration]($style) "
        style      = "bold yellow"

        [nix_shell]
        format = "[$symbol$state]($style) "
        symbol = "❄️ "
        style  = "bold blue"

        [direnv]
        format   = "[$symbol$loaded/$allowed]($style) "
        symbol   = "🔐 "
        style    = "bold yellow"
        disabled = false

        [shell]
        powershell_indicator = "_"
        disabled             = false

        [nodejs]
        format = "[$symbol($version )]($style)"
        symbol = " "

        [python]
        format = "[$symbol$pyenv_prefix($version )(\($virtualenv\) )]($style)"
        symbol = " "

        [rust]
        format = "[$symbol($version )]($style)"
        symbol = " "

        [golang]
        format = "[$symbol($version )]($style)"
        symbol = " "

        [time]
        disabled   = false
        format     = "[$time]($style) "
        time_format= "%H:%M"
        style      = "dimmed white"

        ${
          if cfg.isLaptop
          then ''
            [battery]
            full_symbol        = "🔋"
            charging_symbol    = "⚡"
            discharging_symbol = "💀"

            [[battery.display]]
            threshold = 20
            style     = "bold red"

            [[battery.display]]
            threshold = 50
            style     = "bold yellow"
          ''
          else ''
            [battery]
            disabled = true
          ''
        }

        # ── Disabled modules ────────────────────────────────────────────────
        [conda]
        disabled = true

        [docker_context]
        disabled = true

        [git_commit]
        disabled = true

        [status]
        disabled = true
      '';
    };

    # ── Firefox user.js ──────────────────────────────────────────────────────
    # Firefox profile directory names have a random prefix (e.g.
    # "xxxxxxxx.custom-default"), which win.files can't resolve at build time
    # (it only assembles a fixed tree). Stage the built file under a fixed
    # nix-win-managed path, then a custom activation step finds the real
    # profile dir and copies it in — mirrors the win_find + win_copy pair the
    # Ansible role used.
    win.files.".local/share/nix-win/firefox-user.js" = lib.mkIf cfg.featureFirefox {
      text = builtins.readFile ./firefox-user.js;
    };

    win.activationScripts.firefoxUserJs = lib.mkIf cfg.featureFirefox {
      deps = ["files"];
      text = ''
        Write-Host "nix-win: deploying Firefox user.js..." -ForegroundColor Cyan
        $staged = Join-Path $env:USERPROFILE ".local\share\nix-win\firefox-user.js"
        $profilesRoot = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
        $profileDir = Get-ChildItem -Path $profilesRoot -Directory -Filter "*custom-default*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($profileDir) {
            Copy-Item -Path $staged -Destination (Join-Path $profileDir.FullName "user.js") -Force
        } else {
            Write-Warning "No Firefox profile matching '*custom-default*' found under $profilesRoot — skipping."
        }
      '';
    };
  };
}
