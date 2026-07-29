## Windows registry/explorer/environment/PATH settings shared across hosts.
## Ported from playbooks-4-windows' roles/windows_settings/tasks/{registry,explorer,environment,path}.yml.
##
## IMPORTANT — elevation: every entry below under HKLM (developer mode,
## telemetry, activity feed) and every win.dsc.psdsc.environment entry
## (Machine-scope) requires `nix-win switch` to run from an elevated
## (Administrator) PowerShell/WSL session. HKCU-only entries do not.
##
## IMPORTANT — env var scope change from the Ansible version: the original
## roles/windows_settings/tasks/environment.yml set EDITOR/VISUAL/SHELL/XDG_*
## at User (HKCU\Environment) scope via win_environment. DSC v3's
## PSDesiredStateConfiguration/Environment resource only supports Process or
## Machine targets (see nix-win's modules/environment.nix comment) — there is
## no User-scope DSC equivalent. These are set at Machine scope here instead,
## which means they become visible to every account on the box, not just this
## user. Acceptable on these single-user machines; revisit if that changes.
{config, ...}: let
  home = config.win.user.homeDirectory;
  configHome = "${home}\\.config";

  mkAdvanced = valueName: dword: {
    keyPath = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced";
    inherit valueName;
    valueData.DWord = dword;
  };
in {
  win.dsc.enable = true;

  win.dsc.resource."Microsoft.Windows/Registry" = {
    # ── Developer Mode — symlinks without UAC prompt (HKLM, needs admin) ──
    "Developer Mode".keyPath = "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock";
    "Developer Mode".valueName = "AllowDevelopmentWithoutDevLicense";
    "Developer Mode".valueData.DWord = 1;

    # ── Telemetry / Privacy (HKLM entries need admin) ──────────────────────
    "Telemetry Level".keyPath = "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection";
    "Telemetry Level".valueName = "AllowTelemetry";
    "Telemetry Level".valueData.DWord = 1; # 0=Off 1=Basic 2=Enhanced 3=Full

    "Advertising ID".keyPath = "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo";
    "Advertising ID".valueName = "Enabled";
    "Advertising ID".valueData.DWord = 0; # disabled

    "Activity Feed".keyPath = "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System";
    "Activity Feed".valueName = "EnableActivityFeed";
    "Activity Feed".valueData.DWord = 0; # disabled

    # ── Context Menu — restore full Windows 11 right-click menu ───────────
    "Full Context Menu".keyPath = "HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\\InprocServer32";
    "Full Context Menu".valueData.String = "";

    # ── Taskbar ─────────────────────────────────────────────────────────────
    "Taskbar Combine" = mkAdvanced "TaskbarGlomLevel" 0; # 0=always 1=when full 2=never
    "Taskbar Search".keyPath = "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Search";
    "Taskbar Search".valueName = "SearchboxTaskbarMode";
    "Taskbar Search".valueData.DWord = 0;

    # ── AutoRun hardening — remove CMD AutoRun entirely ────────────────────
    "CMD AutoRun"._exist = false;
    "CMD AutoRun".keyPath = "HKCU:\\SOFTWARE\\Microsoft\\Command Processor";
    "CMD AutoRun".valueName = "AutoRun";

    # ── File Associations ───────────────────────────────────────────────────
    ".toml -> vim".keyPath = "HKCU:\\SOFTWARE\\Classes\\.toml";
    ".toml -> vim".valueData.String = "toml_auto_file";

    # ── Explorer preferences (roles/windows_settings/tasks/explorer.yml) ───
    "Explorer: show extensions" = mkAdvanced "HideFileExt" 0;
    "Explorer: show hidden" = mkAdvanced "Hidden" 1;
    "Explorer: show protected OS files" = mkAdvanced "ShowSuperHidden" 0;
    "Explorer: expand to current folder" = mkAdvanced "NavPaneExpandToCurrentFolder" 1;
    "Explorer: launch to This PC" = mkAdvanced "LaunchTo" 1; # 1=This PC 2=Quick Access
    "Explorer: full path in title bar" = mkAdvanced "FullPath" 1;
    "Explorer: full path in address bar" = mkAdvanced "FullPathAddress" 1;
    "Explorer: disable shake to minimise" = mkAdvanced "DisallowShaking" 1;
  };

  # ── User-scoped env vars, forced to Machine scope — see module header ───
  win.dsc.psdsc.environment = let
    mkEnv = value: {
      Ensure = "Present";
      Target = ["Machine"];
      Value = value;
    };
  in {
    EDITOR = mkEnv "vim";
    VISUAL = mkEnv "vim";
    SHELL = mkEnv "pwsh";
    XDG_CONFIG_HOME = mkEnv configHome;
    XDG_DATA_HOME = mkEnv "${home}\\.local\\share";
    XDG_CACHE_HOME = mkEnv "${home}\\.cache";
    XDG_STATE_HOME = mkEnv "${home}\\.local\\state";
    STARSHIP_CONFIG = mkEnv "${configHome}\\starship.toml";
    GIT_CONFIG_GLOBAL = mkEnv "${configHome}\\git\\config";
  };

  # ── User PATH — order matters, first entry wins (roles/windows_settings/tasks/path.yml) ──
  # MSYS2 itself is still installed as a Scoop package (win.scoop.packages.msys2,
  # see ./packages.nix); only its pacman-managed packages stay on Ansible
  # (playbooks-4-windows' msys2 role) — this PATH entry is independent of that.
  win.environment.userPath = [
    "${home}\\.local\\bin"
    "${home}\\scoop\\shims"
    "${home}\\scoop\\apps\\msys2\\current\\mingw64\\bin"
  ];

  # ── Power plan — not a registry value, so it rides a dedicated activation
  # phase rather than the DSC resource list. Idempotent: powercfg is a no-op
  # if already active.
  win.activationScripts.powerPlan = {
    deps = ["dsc"];
    text = ''
      Write-Host "nix-win: applying power plan..." -ForegroundColor Cyan
      powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
    '';
  };
}
