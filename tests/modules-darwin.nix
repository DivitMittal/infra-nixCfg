# Behavioural tests for modules/hosts/darwin/* evaluated through nix-darwin.
{
  lib,
  pkgs,
  inputs,
  self,
}: let
  evalDarwin = module:
    (inputs.nix-darwin.lib.darwinSystem {
      inherit pkgs;
      modules = [
        self.darwinModules.default
        {
          system = {
            stateVersion = 6;
            primaryUser = "test";
          };
        }
        module
      ];
    }).config;

  fakeBin = name: pkgs.writeShellScriptBin name "";
  kanataPkg = fakeBin "kanata";
  trayPkg = fakeBin "kanata-tray";
  spotifydPkg = fakeBin "spotifyd";

  defaults = evalDarwin {};

  kanata = extra:
    evalDarwin {
      services.kanata =
        {
          enable = true;
          package = kanataPkg;
        }
        // extra;
    };

  tray = evalDarwin {
    services.kanata-tray = {
      enable = true;
      package = trayPkg;
      environment.KANATA_RSCROLL = "1";
    };
  };

  spotifyd = evalDarwin {
    services.spotify-daemon = {
      enable = true;
      package = spotifydPkg;
      settings.global.bitrate = 320;
    };
  };

  buster = cfg: (evalDarwin {system.daemonBuster = {enable = true;} // cfg;}).system.activationScripts.daemonBuster.text;
  disables = domain: svc: script: contains "launchctl disable ${domain}/\"${svc}\"" script;
  enables = domain: svc: script: contains "launchctl enable ${domain}/\"${svc}\"" script;
  ## Store-path context must be dropped before regex matching.
  plain = builtins.unsafeDiscardStringContext;
  contains = needle: haystack: lib.hasInfix (plain needle) (plain haystack);
  matches = regex: s: builtins.match (plain regex) (plain s) != null;
in {
  ## ── kanata ────────────────────────────────────────────────────────────────
  testKanataDisabledByDefault = {
    expr = defaults.launchd.daemons ? kanata;
    expected = false;
  };

  testKanataRunsPackageBinary = {
    expr = contains "${lib.getExe kanataPkg} --nodelay" (kanata {}).launchd.daemons.kanata.script;
    expected = true;
  };

  testKanataWithoutConfigOmitsCfgFlag = {
    expr = contains "--cfg" (kanata {}).launchd.daemons.kanata.script;
    expected = false;
  };

  testKanataWithConfigPassesCfgFlag = {
    expr = matches ".*--cfg /nix/store/[a-z0-9]+-kanata\\.kbd.*" (kanata {config = "(defsrc caps)";}).launchd.daemons.kanata.script;
    expected = true;
  };

  testKanataStartsKarabinerDaemon = {
    expr = (kanata {}).launchd.daemons.karabiner-daemon.serviceConfig.RunAtLoad;
    expected = true;
  };

  testKanataPassesEnvironment = {
    expr = (kanata {environment.FOO = "bar";}).launchd.daemons.kanata.serviceConfig.EnvironmentVariables.FOO or null;
    expected = "bar";
  };

  testKanataInstallsSudoersRule = {
    expr = (kanata {}).environment.etc ? "sudoers.d/kanata";
    expected = true;
  };

  ## ── kanata-tray ───────────────────────────────────────────────────────────
  testKanataTrayDisabledByDefault = {
    expr = defaults.launchd.user.agents ? kanata-tray;
    expected = false;
  };

  testKanataTrayRunsTrayBinary = {
    expr = tray.launchd.user.agents.kanata-tray.command;
    expected = "sudo --preserve-env ${trayPkg}/bin/kanata-tray";
  };

  testKanataTrayPassesEnvironment = {
    expr = tray.launchd.user.agents.kanata-tray.environment;
    expected = {KANATA_RSCROLL = "1";};
  };

  testKanataTrayInstallsSudoersRule = {
    expr = tray.environment.etc ? "sudoers.d/kanata-tray";
    expected = true;
  };

  ## ── spotify-daemon ────────────────────────────────────────────────────────
  testSpotifyDaemonDisabledByDefault = {
    expr = defaults.launchd.user.agents ? spotify-daemon;
    expected = false;
  };

  testSpotifyDaemonRunsPackageBinaryWithConfig = {
    expr = matches "${lib.escapeRegex (lib.getExe spotifydPkg)} --no-daemon --config-path /nix/store/[a-z0-9]+-spotifyd\\.toml" spotifyd.launchd.user.agents.spotify-daemon.script;
    expected = true;
  };

  ## ── daemon-buster ─────────────────────────────────────────────────────────
  testDaemonBusterDisabledByDefault = {
    expr = defaults.system.activationScripts ? daemonBuster && defaults.system.activationScripts.daemonBuster.text != "";
    expected = false;
  };

  testDaemonBusterGroupsDefaultToKeep = {
    expr = lib.filterAttrs (_: v: v) defaults.system.daemonBuster.disable;
    expected = {};
  };

  testDaemonBusterNothingDisabledWithoutOptIn = {
    expr = contains "launchctl disable" (buster {});
    expected = false;
  };

  testDaemonBusterReEnablesKnownServicesByDefault = {
    expr = enables "gui/501" "com.apple.weatherd" (buster {});
    expected = true;
  };

  testDaemonBusterDisablesOptedInGroup = {
    expr = let
      s = buster {disable.weather = true;};
    in
      disables "gui/501" "com.apple.weatherd" s && !(enables "gui/501" "com.apple.weatherd" s);
    expected = true;
  };

  testDaemonBusterUsesSystemDomain = {
    expr = disables "system" "com.apple.adid" (buster {disable.advertising = true;});
    expected = true;
  };

  testDaemonBusterUsesPreLoginDomain = {
    expr = disables "user/205" "com.apple.geod" (buster {disable.location = true;});
    expected = true;
  };

  testDaemonBusterLeavesOtherGroupsAlone = {
    expr = disables "gui/501" "com.apple.weatherd" (buster {disable.advertising = true;});
    expected = false;
  };

  testDaemonBusterCarveOutWins = {
    expr = let
      s = buster {
        disable.location = true;
        extra.enable = ["com.apple.CoreLocationAgent"];
      };
    in {
      carvedOut = disables "gui/501" "com.apple.CoreLocationAgent" s;
      reEnabled = enables "gui/501" "com.apple.CoreLocationAgent" s;
      siblingStillDisabled = disables "gui/501" "com.apple.navd" s;
    };
    expected = {
      carvedOut = false;
      reEnabled = true;
      siblingStillDisabled = true;
    };
  };

  testDaemonBusterExtraDisable = {
    expr = disables "system" "com.example.custom" (buster {extra.disable.system = ["com.example.custom"];});
    expected = true;
  };

  testDaemonBusterDeduplicatesServices = {
    expr = let
      ## com.apple.dprivacyd appears twice in analytics (user + system) and once
      ## more via extra; within one domain it must be disabled exactly once.
      s = buster {
        disable.analytics = true;
        extra.disable.user = ["com.apple.dprivacyd"];
      };
    in
      lib.length (lib.filter (l: l == "launchctl disable gui/501/\"com.apple.dprivacyd\" || true") (map lib.trim (lib.splitString "\n" s)));
    expected = 1;
  };
}
