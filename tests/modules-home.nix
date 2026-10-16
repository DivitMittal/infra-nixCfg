# Behavioural tests for modules/home/* evaluated through home-manager.
{
  lib,
  pkgs,
  inputs,
  self,
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  evalHome = module:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      ## mkCfg passes hostPlatform as a special arg.
      extraSpecialArgs = {inherit (pkgs.stdenv) hostPlatform;};
      modules = [
        self.homeManagerModules.default
        {
          home = {
            username = "test";
            homeDirectory =
              if isDarwin
              then "/Users/test"
              else "/home/test";
            stateVersion = "25.05";
          };
        }
        module
      ];
    }).config;

  fake = pkgs.writeShellScriptBin "fake-tool" "";
  hasPkg = cfg: builtins.elem fake cfg.home.packages;
  hasNull = cfg: builtins.elem null cfg.home.packages;

  settings = {
    a = 1;
    nested.b = "x";
  };

  ## Modules that follow the `enable / package (nullable) / settings` shape,
  ## mapped to the file their settings are written to.
  xdg = file: {
    inherit file;
    at = ["xdg" "configFile"];
  };
  standard = {
    discordo =
      if isDarwin
      then {
        at = ["home" "file"];
        file = "Library/Application Support/discordo/config.toml";
      }
      else xdg "discordo/config.toml";
    glow = xdg "glow/glow.yaml";
    ov = xdg "ov/config.yaml";
    spotatui = xdg "spotatui/config.yml";
    spotifyd = xdg "spotifyd/spotifyd.toml";
    warpd = xdg "warpd/config";
  };

  fileOf = name: cfg: let
    inherit (standard.${name}) at file;
  in
    (lib.getAttrFromPath at cfg).${file} or null;

  perModule = name: let
    T = lib.toUpper (lib.substring 0 1 name) + lib.substring 1 (-1) name;
    on = extra: evalHome {programs.${name} = {enable = true;} // extra;};
  in {
    "test${T}DisabledByDefault" = {
      expr = (evalHome {}).programs.${name}.enable;
      expected = false;
    };
    "test${T}InstallsPackage" = {
      expr = hasPkg (on {package = fake;});
      expected = true;
    };
    "test${T}NullPackageInstallsNothing" = {
      expr = hasNull (on {package = null;});
      expected = false;
    };
    "test${T}WritesSettingsFile" = {
      expr =
        fileOf name (on {
          package = fake;
          inherit settings;
        })
        != null;
      expected = true;
    };
    "test${T}DisabledWritesNothing" = {
      expr = let
        cfg = evalHome {programs.${name} = {inherit settings;};};
      in
        fileOf name cfg == null && !(hasPkg cfg);
      expected = true;
    };
  };

  warpd = evalHome {
    programs.warpd = {
      enable = true;
      package = fake;
      settings = {
        left = "n";
        speed = 220;
      };
    };
  };

  wikiTui = s:
    evalHome {
      programs.wiki-tui = {
        enable = true;
        package = fake;
        settings = s;
      };
    };
in
  lib.concatMapAttrs (name: _: perModule name) standard
  // {
    ## Settings that are empty should not produce an (empty) config file.
    testGlowEmptySettingsWritesNoFile = {
      expr = (evalHome {programs.glow.enable = true;}).xdg.configFile ? "glow/glow.yaml";
      expected = false;
    };

    testDiscordoUsesPlatformConfigLocation = {
      expr = let
        cfg = evalHome {
          programs.discordo = {
            enable = true;
            package = fake;
            inherit settings;
          };
        };
      in {
        appSupport = cfg.home.file ? "Library/Application Support/discordo/config.toml";
        xdg = cfg.xdg.configFile ? "discordo/config.toml";
      };
      expected = {
        appSupport = isDarwin;
        xdg = !isDarwin;
      };
    };

    testWarpdRendersKeyValueLines = {
      expr = warpd.xdg.configFile."warpd/config".text;
      expected = "left: n\nspeed: 220";
    };

    testWikiTuiTargetsPlatformConfigDir = {
      expr = (wikiTui settings).home.file.wiki-tui.target;
      expected =
        if isDarwin
        then "Library/Application Support/com.builditluc.wiki-tui/config.toml"
        else ".config/wiki-tui/config.toml";
    };

    testWikiTuiEmptySettingsDisablesFile = {
      expr = (wikiTui {}).home.file.wiki-tui.enable;
      expected = false;
    };

    testWikiTuiNullPackageInstallsNothing = {
      expr = hasNull (evalHome {
        programs.wiki-tui = {
          enable = true;
          package = null;
        };
      });
      expected = false;
    };
  }
