## Bootstrap Windows PowerShell 5.1's NuGet provider before nix-win installs
## win.powershell.modules.windowsPowerShell. A fresh Windows lacks it, and
## Install-Module then waits on its install prompt inside the hidden deploy
## task, so the switch hangs. Install-Module -Force, which nix-win passes,
## already skips the untrusted-PSGallery prompt.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf (config.win.powershell.modules.windowsPowerShell != {}) {
    win.activationScripts.psmodules.text = lib.mkBefore ''
      Write-Host "nix-win: ensuring the NuGet provider for Windows PowerShell..." -ForegroundColor Cyan
      powershell.exe -NoProfile -NonInteractive -Command "if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope AllUsers -Force | Out-Null }"
      if ($LASTEXITCODE -ne 0) { throw "nix-win: installing the NuGet provider failed ($LASTEXITCODE)" }
    '';
  };
}
