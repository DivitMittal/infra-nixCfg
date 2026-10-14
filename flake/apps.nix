{
  inputs,
  lib,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs.stdenvNoCC) hostPlatform;
    inherit (lib.attrsets) mergeAttrsList optionalAttrs;

    ## Mirror the pkgs/lib extensions mkCfg applies for the "home" class so the
    ## home modules see the same channels (master/stable), the NUR overlay, and the
    ## pkgs-applied lib.custom helpers they expect.
    pkgs' = pkgs.extend (
      final: prev:
        mergeAttrsList [
          {
            master = inputs.nixpkgs-master.legacyPackages.${hostPlatform.system};
            stable = inputs."nixpkgs-2605".legacyPackages.${hostPlatform.system};
          }
          (inputs.nur.overlays.default final prev)
          (optionalAttrs hostPlatform.isDarwin (inputs.brew-nix.overlays.default final prev))
        ]
    );
    lib' = lib.extend (_: prev: {
      custom =
        prev.custom
        // {
          mkZbxBin = prev.custom.mkZbxBin pkgs';
          mkUvxBin = prev.custom.mkUvxBin pkgs';
          mkBunxBin = prev.custom.mkBunxBin pkgs';
        };
    });

    ## Identity is derived from the invoking user's environment so the apps are
    ## user-agnostic: run with `--impure` (e.g. `nix run --impure .#tty`) and the
    ## stub adapts to whoever runs it; in pure evaluation it falls back to generic
    ## placeholders. None of these values change the resulting package set — they
    ## only satisfy hostSpec/home-manager assertions during evaluation.
    envOr = name: default: let
      value = builtins.getEnv name;
    in
      if value == ""
      then default
      else value;

    username = envOr "USER" "user";
    homeDir = envOr "HOME" (
      if hostPlatform.isDarwin
      then "/Users/${username}"
      else "/home/${username}"
    );

    ## Defines the hostSpec option type inline, replacing common/all/hostSpec.nix
    ## (which pulls from the private secrets input). Values are environment-derived
    ## stubs — sufficient for package enumeration; secret-backed config files won't
    ## activate.
    hostSpecStub = {lib, ...}: {
      options.hostSpec = with lib; {
        username = mkOption {type = types.str;};
        userFullName = mkOption {type = types.str;};
        handle = mkOption {type = types.str;};
        home = mkOption {type = types.str;};
        hostName = mkOption {type = types.str;};
        email = {
          dev = mkOption {type = types.str;};
          personal = mkOption {type = types.str;};
        };
      };
      config.hostSpec = {
        inherit username;
        userFullName = username;
        handle = username;
        home = homeDir;
        hostName = "env";
        email = {
          dev = "${username}@env.local";
          personal = "${username}@env.local";
        };
      };
    };

    ## Evaluate a home-manager config directly in perSystem, bypassing withSystem
    ## to avoid the circular dependency that mkCfg introduces. Directories are
    ## pulled in via import-tree (matching mkCfg) because they have no default.nix
    ## and cannot be imported as bare module paths.
    mkEnvApp = name: additionalModules: let
      cfg = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs';
        lib = lib';
        extraSpecialArgs = {inherit inputs self hostPlatform;};
        modules =
          [
            hostSpecStub
            ## common/home/conf.nix manages nix.conf, which requires a concrete
            ## nix.package in standalone home-manager (normally supplied by common/all).
            {nix.package = pkgs'.nix;}
            (inputs.import-tree (self + "/common/home")) # hm.nix, helpers.nix, age.nix, conf.nix, stylix.nix
            self.outputs.homeManagerModules.default
          ]
          ++ additionalModules;
      };
      env = pkgs'.buildEnv {
        name = "${name}-env";
        paths = lib'.filter (p: p != null) cfg.config.home.packages;
        pathsToLink = ["/bin" "/share"];
        ignoreCollisions = true;
      };
    in {
      type = "app";
      program = toString (pkgs'.writeShellScript name ''
        export PATH="${env}/bin:$PATH"
        exec "''${SHELL:-${pkgs'.bashInteractive}/bin/bash}"
      '');
    };
  in {
    apps =
      {
        tty = mkEnvApp "tty" [(inputs.import-tree (self + "/home/tty"))];
      }
      ## Desktop is Linux-only — compositor stack doesn't exist on Darwin
      // lib.optionalAttrs hostPlatform.isLinux {
        desktop = mkEnvApp "desktop" [
          (inputs.import-tree (self + "/home/tty"))
          (inputs.import-tree (self + "/home/gui/linux"))
        ];
      };
  };
}
