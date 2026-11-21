## Lan Mouse on L2's Windows boot: its half of the desk in lib/lan-mouse.nix.
{
  self,
  lib,
  pkgs,
  ...
}: let
  desk = import (self + "/lib/lan-mouse.nix") {inherit lib;};
  spec = desk.windows.L2;
  configFile = (pkgs.formats.toml {}).generate "lan-mouse-config.toml" spec.config;
in {
  win.files."lan-mouse/config.toml" = {
    source = configFile;
    targetRoot = "appdata-local";
  };

  # The task is registered here rather than through win.dsc.scheduledTasks:
  # that resource runs as SYSTEM unless given a stored password, and Lan Mouse
  # must run in vanee's interactive session to capture and inject input.
  # nix-win activates in that session, so the current identity is the right one.
  win.activationScripts.serviceReloads.text = lib.mkAfter ''
    Write-Host "nix-win: registering Lan Mouse..." -ForegroundColor Cyan
    $lanMouse = Join-Path $env:USERPROFILE '${spec.executable}'
    $lanMouseTask = '${spec.task.name}'
    if (-not (Test-Path $lanMouse)) {
        Write-Warning "Lan Mouse is not installed at $lanMouse; its login task was not registered."
    } else {
        $directory = Join-Path $env:LOCALAPPDATA 'lan-mouse'
        $daemon = '"{0}" -c "{1}\config.toml" daemon >> "{1}\daemon.log" 2>&1' -f $lanMouse, $directory
        # A headless conhost gives the console daemon a console with no window.
        # powershell -WindowStyle Hidden is ignored when Windows Terminal is the
        # default console host, which left a blank window open while it ran.
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\conhost.exe') `
            -Argument ('--headless "{0}" /d /s /c "{1}"' -f $env:ComSpec, $daemon)
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel ${spec.task.runLevel}
        $settings = New-ScheduledTaskSettingsSet -RestartCount ${toString spec.task.restartCount} `
            -RestartInterval (New-TimeSpan -Minutes ${toString spec.task.restartIntervalMinutes}) `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $lanMouseTask -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        # The PowerShell launcher from utils/lan_mouse_windows.ps1 is superseded.
        Remove-Item (Join-Path $directory 'start.ps1') -ErrorAction SilentlyContinue
        # Restart now so a changed config or task applies without logging out.
        # Stopping the task does not always reach the daemon it started.
        Stop-ScheduledTask -TaskName $lanMouseTask
        Get-Process -Name lan-mouse -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-ScheduledTask -TaskName $lanMouseTask
    }
  '';
}
