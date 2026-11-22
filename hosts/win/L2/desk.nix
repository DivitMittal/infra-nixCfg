## Desk daemons on L2's Windows boot (./lan-mouse.nix, ./uniclipboard.nix).
## Each one declared under desk.daemons gets, through nix-win's DSC resources:
## a login task in vanee's session, an inbound firewall rule, and removal of
## the Block rules Windows' network prompt leaves behind. Only the restart
## after a deploy stays imperative, since DSC has no resource for it.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.desk.daemons;
  user = config.win.user.name;
  system32 = "C:\\Windows\\System32";

  daemon = types.submodule ({config, ...}: {
    options = {
      executable = mkOption {
        type = types.str;
        description = "Absolute path of the executable the login task runs.";
      };
      arguments = mkOption {
        type = types.str;
        default = "";
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
      };
      listener = mkOption {
        type = types.str;
        default = config.executable;
        description = "Absolute path of the executable that accepts inbound traffic.";
      };
      log = mkOption {
        type = types.str;
        description = "Absolute path the daemon's stdout and stderr are appended to.";
      };
      processes = mkOption {
        type = types.listOf types.str;
        description = "Process names stopped before the task restarts.";
      };
      runLevel = mkOption {
        type = types.enum ["Limited" "Highest"];
        default = "Limited";
      };
      restartCount = mkOption {
        type = types.int;
        default = 3;
      };
      restartIntervalMinutes = mkOption {
        type = types.int;
        default = 1;
      };
    };
  });

  taskFor = name: d: let
    environment = lib.concatStrings (lib.mapAttrsToList (key: value: "set ${key}=${value}&& ") d.environment);
    command = ''${environment}"${d.executable}" ${d.arguments} >> "${d.log}" 2>&1'';
  in {
    Ensure = "Present";
    Enable = true;
    Description = "${name}, managed by nix-win.";
    # A headless conhost gives the console daemon no window at all.
    # powershell -WindowStyle Hidden is ignored when Windows Terminal is the
    # default console host, which left a blank window open while it ran.
    ActionExecutable = "${system32}\\conhost.exe";
    ActionArguments = ''--headless "${system32}\cmd.exe" /d /s /c "${command}"'';
    ScheduleType = "AtLogon";
    User = user;
    # Interactive runs the task in vanee's desktop session, where the daemons
    # can capture input and reach the clipboard. ComputerManagementDsc never
    # reads the password for Interactive tasks, but PSCredential needs one.
    LogonType = "Interactive";
    ExecuteAsCredential = {
      UserName = user;
      Password = "unused-for-interactive-logon";
    };
    RunLevel = d.runLevel;
    MultipleInstances = "IgnoreNew";
    ExecutionTimeLimit = "00:00:00";
    RestartCount = d.restartCount;
    RestartInterval = "00:${lib.fixedWidthNumber 2 d.restartIntervalMinutes}:00";
    AllowStartIfOnBatteries = true;
    DontStopIfGoingOnBatteries = true;
    StartWhenAvailable = true;
  };

  # L2's wired LAN is classed Public, so without a rule each daemon's first
  # listen raises Windows' "allow on public networks" prompt. Access stays
  # limited to the local subnet rather than reclassifying the LAN as Private,
  # whose firewall profile is off on L2.
  ruleFor = name: d:
    lib.nameValuePair "nix-win ${name}" {
      DisplayName = "nix-win: ${name}";
      Group = "nix-win";
      Ensure = "Present";
      Enabled = "True";
      Action = "Allow";
      Direction = "Inbound";
      Profile = ["Any"];
      Program = d.listener;
      RemoteAddress = ["LocalSubnet"];
    };

  psList = items: "@(" + lib.concatMapStringsSep ", " (item: "'${item}'") items + ")";
  # Dismissing the prompt records Block rules for the executable under
  # generated names, and Block wins over any Allow, so no Firewall resource can
  # target them. -contains compares paths case-insensitively, as Windows does.
  promptBlocks = ''
    @(Get-NetFirewallApplicationFilter -PolicyStore PersistentStore |
        Where-Object { ${psList (lib.mapAttrsToList (_: d: d.listener) cfg)} -contains $_.Program } |
        Get-NetFirewallRule | Where-Object { $_.Action -eq 'Block' })
  '';
in {
  options.desk.daemons = mkOption {
    type = types.attrsOf daemon;
    default = {};
    description = "Desk daemons run at logon, keyed by scheduled task name.";
  };

  config = lib.mkIf (cfg != {}) {
    # The DSC resources below run through Windows PowerShell 5.1; versions
    # match the schemas nix-win generated its options from.
    win.powershell.modules.windowsPowerShell = {
      ComputerManagementDsc = "10.0.0";
      NetworkingDsc = "9.0.0";
    };

    win.dsc.scheduledTasks = lib.mapAttrs taskFor cfg;
    win.dsc.firewall.rules = lib.mapAttrs' ruleFor cfg;
    win.dsc.psdsc.script."nix-win desk prompt blocks" = {
      # Parenthesised: promptBlocks spans lines, and a bare `.Count` on its
      # own line would parse as a command.
      GetScript = "@{ Result = [string](${promptBlocks}).Count }";
      TestScript = "(${promptBlocks}).Count -eq 0";
      SetScript = "${promptBlocks} | Remove-NetFirewallRule";
    };

    # Restart so a new binary or config takes over without logging out.
    # Stopping a task does not always reach the daemon it started.
    win.activationScripts.serviceReloads.text = lib.mkAfter ''
      Write-Host "nix-win: restarting desk daemons..." -ForegroundColor Cyan
      ${lib.concatStrings (lib.mapAttrsToList (name: d: ''
          Stop-ScheduledTask -TaskName '${name}'
          Get-Process -Name ${lib.concatStringsSep ", " d.processes} -ErrorAction SilentlyContinue | Stop-Process -Force
          Start-ScheduledTask -TaskName '${name}'
        '')
        cfg)}
    '';
  };
}
