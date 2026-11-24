param(
    [string]$ConfigurationPath = (Join-Path $PSScriptRoot 'L2.json'),
    [switch]$Install
)

$ErrorActionPreference = 'Stop'
$spec = Get-Content -Raw $ConfigurationPath | ConvertFrom-Json
if ($spec.mouseKeys -isnot [bool]) {
    throw 'The Windows declaration must specify mouseKeys as a Boolean.'
}
if ($Install) {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}" -ConfigurationPath "{2}"' -f $powershell, $PSCommandPath, $ConfigurationPath
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $spec.task.runLevel
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $taskName = $spec.task.name + ' Cursor'
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    return
}

# This must run in the interactive desktop session. Updating the registry over
# SSH alone does not update the active session's cursor rendering.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LanMouseCursor {
    [StructLayout(LayoutKind.Sequential)]
    public struct MouseKeys {
        public uint cbSize, flags, maxSpeed, timeToMaxSpeed, ctrlSpeed;
        public uint reserved1, reserved2;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct CursorInfo {
        public uint cbSize, flags;
        public IntPtr cursor;
        public int x, y;
    }
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint size, ref MouseKeys value, uint update);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetCursorInfo(ref CursorInfo value);
}
'@

$settings = New-Object LanMouseCursor+MouseKeys
$settings.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($settings)
if (-not [LanMouseCursor]::SystemParametersInfo(0x0036, $settings.cbSize, [ref]$settings, 0)) {
    throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
$previousFlags = $settings.flags
if ($spec.mouseKeys) {
    $settings.flags = $settings.flags -bor 1
} else {
    $settings.flags = $settings.flags -band 0xFFFFFFFE
}
if ($settings.flags -ne $previousFlags) {
    if (-not [LanMouseCursor]::SystemParametersInfo(0x0037, $settings.cbSize, [ref]$settings, 3)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}
$cursor = New-Object LanMouseCursor+CursorInfo
$cursor.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($cursor)
if (-not [LanMouseCursor]::GetCursorInfo([ref]$cursor)) {
    throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
$result = [pscustomobject]@{
    mouseKeysEnabled = (($settings.flags -band 1) -ne 0)
    previousFlags = $previousFlags
    flags = $settings.flags
    cursorVisible = (($cursor.flags -band 1) -ne 0)
} | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'cursor-state.json'), $result)
$result
