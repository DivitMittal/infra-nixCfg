## Package lists shared across all Windows hosts.
## Ported from playbooks-4-windows' common/packages.yml. MSYS2 packages are
## NOT ported here — MSYS2 stays on Ansible (roles/msys2), invoked separately;
## see playbooks-4-windows' feat/nix-win-migration branch.
{
  win.scoop = {
    enable = true;

    buckets = {
      main = "https://github.com/ScoopInstaller/Main";
      extras = "https://github.com/ScoopInstaller/Extras";
      nerd-fonts = "https://github.com/ScoopInstaller/Nerd-Fonts";
      versions = "https://github.com/ScoopInstaller/Versions";
    };

    packages = {
      # ── Development ──────────────────────────────────────────────────────
      git.bucket = "main";
      nodejs.bucket = "main";
      python.bucket = "main";
      vim.bucket = "main";
      pwsh.bucket = "main";

      # ── CLI Utilities ────────────────────────────────────────────────────
      "7zip".bucket = "main";
      ouch.bucket = "main";
      nircmd.bucket = "main";
      sudo.bucket = "main";
      innounp.bucket = "main";
      psshutdown.bucket = "extras";

      # ── Dev Environment ──────────────────────────────────────────────────
      msys2.bucket = "main";
      mingw-winlibs-llvm-ucrt.bucket = "main";
      whkd.bucket = "extras";

      # ── Applications ─────────────────────────────────────────────────────
      wezterm.bucket = "extras";
      firefox.bucket = "extras";
      starship.bucket = "main";
      fastfetch.bucket = "extras";
      dark.bucket = "extras";
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
    };
  };
}
