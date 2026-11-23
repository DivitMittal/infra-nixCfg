## Package lists shared across all Windows hosts.
##
## Windows vs WSL split: Windows gets what has to touch Windows itself (GUI
## apps, games, hardware tools, terminal/shell integration, networking
## agents) plus what scoop and nix-win need (git, 7zip, pwsh). Language
## toolchains and Linux CLI/TUI tools live in the host's NixOS-WSL distro
## instead (e.g. hosts/nixos/L2W), so each exists on one side only.
## Undeclared scoop apps are left alone (win.scoop.cleanup stays "none").
{
  win.scoop = {
    enable = true;

    buckets = {
      main = "https://github.com/ScoopInstaller/Main";
      extras = "https://github.com/ScoopInstaller/Extras";
      nerd-fonts = "https://github.com/matthewjberger/scoop-nerd-fonts"; # scoop's known nerd-fonts bucket
      versions = "https://github.com/ScoopInstaller/Versions";
    };

    packages = {
      # ── Development ──────────────────────────────────────────────────────
      # Toolchains (node, python, …) are in WSL; vim is $EDITOR in pwsh.
      git.bucket = "main";
      vim.bucket = "main";
      pwsh.bucket = "main";

      # ── CLI Utilities ────────────────────────────────────────────────────
      "7zip".bucket = "main";
      nircmd.bucket = "main";
      sudo.bucket = "main";
      innounp.bucket = "main";
      sysinternals.bucket = "extras"; # includes PsShutdown; no standalone manifest

      # ── Dev Environment ──────────────────────────────────────────────────
      msys2.bucket = "main";
      mingw-winlibs-llvm-ucrt.bucket = "versions";
      whkd.bucket = "extras";

      # ── Applications ─────────────────────────────────────────────────────
      wezterm.bucket = "extras";
      firefox.bucket = "extras";
      starship.bucket = "main";
      fastfetch.bucket = "main";
      dark.bucket = "main";
      onlyoffice-desktopeditors.bucket = "extras";
      localsend.bucket = "extras";

      # ── Fonts ────────────────────────────────────────────────────────────
      "Cascadia-Code".bucket = "nerd-fonts";
    };
  };

  win.winget = {
    enable = true;
    # nix-win's generated install script always passes --silent
    # --accept-source-agreements --accept-package-agreements, so the old
    # `override: "--silent"` on VS Code is already covered unconditionally.
    packages = {
      "Microsoft.WindowsTerminal" = {};
      "Microsoft.PowerBI" = {};
      "Microsoft.VisualStudioCode" = {};
      "Microsoft.VCRedist.2015+.x64" = {};
      "Microsoft.VCRedist.2015+.x86" = {};
      "Microsoft.DotNet.Runtime.8" = {};
      # DSC v3. Without it nix-win skips the win.dsc phase (registry settings
      # in settings.nix) with only a warning. Installed before that phase,
      # but only on PATH from the next switch on.
      "Microsoft.DSC" = {};
    };
  };
}
