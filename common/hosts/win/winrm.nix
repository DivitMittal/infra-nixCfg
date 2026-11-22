## Start WinRM, listening on loopback only, before nix-win applies DSC.
##
## DSC v3's Microsoft.Windows/WindowsPowerShell adapter calls Windows
## PowerShell's Invoke-DscResource, which reaches the local configuration
## manager over WinRM. With the service stopped (the default on client
## Windows), every PSDSC resource fails with "The client cannot connect to the
## destination", which nix-win does not report. Loopback listeners are all
## that local DSC needs; nothing here opens WinRM to the network.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.win.dsc.enable {
    win.activationScripts.dsc.text = lib.mkMerge [
      (lib.mkBefore ''
        Write-Host "nix-win: ensuring loopback WinRM for Windows PowerShell DSC..." -ForegroundColor Cyan
        Set-Service -Name WinRM -StartupType Automatic
        Start-Service -Name WinRM
        $winrmListeners = @(Get-WSManInstance -ResourceURI winrm/config/Listener -Enumerate)
        foreach ($address in 'IP:127.0.0.1', 'IP:[::1]') {
            $present = $winrmListeners | Where-Object { $_.Transport -eq 'HTTP' -and $_.Address -eq $address.Replace('[', "").Replace(']', "") }
            if (-not $present) {
                New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{ Address = $address; Transport = 'HTTP' } | Out-Null
            }
        }
      '')

      # nix-win ignores `dsc config set`'s exit code, so a failing resource
      # used to leave the switch reporting success. Its PATH restore after dsc
      # runs no native command, so $LASTEXITCODE is still dsc's here.
      (lib.mkAfter ''
        if ((Get-Command dsc -ErrorAction SilentlyContinue) -and $LASTEXITCODE -ne 0) {
            throw "nix-win: dsc config set failed with exit code $LASTEXITCODE; see the DSC errors above"
        }
      '')
    ];
  };
}
