## UniClipboard on L2's Windows boot, joining L1 and T2's shared clipboard
## (home/tools/hid/uniclipboard.nix). `uniclip service` only manages systemd
## and launchd, so the daemon gets a login task here instead.
{
  self,
  lib,
  pkgs,
  ...
}: let
  source = (pkgs.callPackage (self + "/pkgs/_sources/generated.nix") {}).uniclipboard-cli-x86_64-windows;
  package = pkgs.runCommand "uniclipboard-cli-windows-${source.version}" {nativeBuildInputs = [pkgs.unzip];} ''
    mkdir -p $out/bin
    unzip -q ${source.src} uniclip.exe uniclipd.exe -d $out/bin
  '';
  taskName = "UniClipboard";
in {
  # Lands in %LOCALAPPDATA%\uniclipboard\bin, which nix-win adds to the user
  # PATH so `uniclip space join` works from any terminal.
  win.packages.uniclipboard.package = package;

  # Registered the same way as Lan Mouse (see ./lan-mouse.nix): in vanee's
  # session, through a headless conhost so no console window stays open.
  win.activationScripts.serviceReloads.text = lib.mkAfter ''
    Write-Host "nix-win: registering UniClipboard..." -ForegroundColor Cyan
    $uniclip = Join-Path $env:LOCALAPPDATA 'uniclipboard\bin\uniclip.exe'
    if (-not (Test-Path $uniclip)) {
        Write-Warning "UniClipboard is missing at $uniclip; its login task was not registered."
    } else {
        $logDirectory = Join-Path $env:LOCALAPPDATA 'uniclipboard'
        # The environment `uniclip service start` sets on macOS and Linux.
        $daemon = 'set UNICLIPBOARD_ENV=production&& set UC_CONSOLE_LOG=off&& "{0}" run >> "{1}\daemon.log" 2>&1' -f $uniclip, $logDirectory
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\conhost.exe') `
            -Argument ('--headless "{0}" /d /s /c "{1}"' -f $env:ComSpec, $daemon)
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName '${taskName}' -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        # Restart so an upgraded binary takes over now. The CLI also spawns a
        # daemon on demand, which would make `uniclip run` refuse to start.
        Stop-ScheduledTask -TaskName '${taskName}'
        Get-Process -Name uniclip, uniclipd -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-ScheduledTask -TaskName '${taskName}'
    }
  '';
}
