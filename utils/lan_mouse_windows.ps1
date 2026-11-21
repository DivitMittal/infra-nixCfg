# Run as the Windows desktop user. The task must run in that user's interactive
# session: a daemon launched directly over SSH cannot capture desktop input.
param(
    [string]$ConfigurationPath = (Join-Path $PSScriptRoot 'L2.json')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$spec = Get-Content -Raw $ConfigurationPath | ConvertFrom-Json
$directory = Join-Path $env:LOCALAPPDATA 'lan-mouse'
$binary = Join-Path $env:USERPROFILE $spec.executable
if (-not (Test-Path $binary)) {
    throw "Lan Mouse is missing: $binary"
}
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$configPath = Join-Path $directory 'config.toml'
# The desired state comes from lib/lan-mouse.nix, exported as L2.json.
$lines = @(
    "port = $($spec.config.port)",
    ('release_bind = ' + (ConvertTo-Json -InputObject @($spec.config.release_bind) -Compress)),
    '',
    '[authorized_fingerprints]'
)
foreach ($property in $spec.config.authorized_fingerprints.PSObject.Properties) {
    $lines += ('"{0}" = "{1}"' -f $property.Name, $property.Value)
}
foreach ($client in $spec.config.clients) {
    $lines += @(
        '', '[[clients]]',
        ('ips = ' + (ConvertTo-Json -InputObject @($client.ips) -Compress)),
        ('position = "{0}"' -f $client.position),
        "port = $($client.port)",
        ('activate_on_startup = ' + $client.activate_on_startup.ToString().ToLowerInvariant())
    )
}
$configuration = ($lines -join "`n") + "`n"
if (-not (Test-Path $configPath) -or [IO.File]::ReadAllText($configPath) -cne $configuration) {
    if (Test-Path $configPath) {
        Copy-Item $configPath "$configPath.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    }
    [IO.File]::WriteAllText($configPath, $configuration)
}
$launcherPath = Join-Path $directory 'start.ps1'
$launcher = @'
$ErrorActionPreference = 'Stop'
$directory = Join-Path $env:LOCALAPPDATA 'lan-mouse'
# Windows PowerShell treats native stderr (including INFO logs) as errors.
# Let cmd redirect the streams so logging cannot terminate the daemon.
$command = '""{0}" -c "{1}" daemon >> "{2}" 2>&1"' -f "__LAN_MOUSE_EXECUTABLE__", "$directory\config.toml", "$directory\daemon.log"
& $env:ComSpec /d /s /c $command
exit $LASTEXITCODE
'@
[IO.File]::WriteAllText($launcherPath, $launcher.Replace('__LAN_MOUSE_EXECUTABLE__', $binary))
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $spec.task.runLevel
$settings = New-ScheduledTaskSettingsSet -RestartCount $spec.task.restartCount -RestartInterval (New-TimeSpan -Minutes $spec.task.restartIntervalMinutes) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $spec.task.name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
# Restart through the interactive task rather than inheriting the SSH session.
Stop-ScheduledTask -TaskName $spec.task.name
Get-Process -Name lan-mouse -ErrorAction SilentlyContinue | Stop-Process
Start-ScheduledTask -TaskName $spec.task.name
Get-ScheduledTask -TaskName $spec.task.name | Select-Object TaskName, State
