## Inbound firewall rules for the desk daemons on L2's Windows boot.
##
## L2's wired LAN is classed Public, so each daemon's first listen raises
## Windows' "allow on public networks" prompt. Dismissing it records Block
## rules for that executable, and Block wins over any Allow. Declaring the
## rules here means the prompt never appears. Access stays limited to the
## local subnet rather than reclassifying the LAN as Private, whose firewall
## profile is off on L2.
{
  self,
  lib,
  ...
}: let
  desk = import (self + "/lib/lan-mouse.nix") {inherit lib;};
  # PowerShell expressions for each daemon's executable.
  programs = {
    "Lan Mouse" = "Join-Path $env:USERPROFILE '${desk.windows.L2.executable}'";
    "UniClipboard" = "Join-Path $env:LOCALAPPDATA 'uniclipboard\\bin\\uniclipd.exe'";
  };
  ruleFor = name: program: ''
    $program = ${program}
    # Replace every rule bound to this executable, including the Block rules
    # a dismissed prompt leaves behind.
    $filters | Where-Object { $_.Program -eq $program } | Get-NetFirewallRule | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'nix-win: ${name}' -Group 'nix-win' -Direction Inbound -Action Allow `
        -Program $program -Profile Any -RemoteAddress LocalSubnet | Out-Null
  '';
in {
  # Before the daemons restart later in serviceReloads, so they never listen
  # without a rule. nix-win runs activation elevated.
  win.activationScripts.serviceReloads.text = lib.mkBefore ''
    Write-Host "nix-win: declaring desk firewall rules..." -ForegroundColor Cyan
    $filters = @(Get-NetFirewallApplicationFilter -PolicyStore PersistentStore)
    ${lib.concatStrings (lib.mapAttrsToList ruleFor programs)}
  '';
}
