{
  pkgs,
  lib,
  inputs,
  config,
  hostPlatform,
  ...
}: let
  inherit (lib) mkIf;
in {
  programs.fish.functions = mkIf (config.programs.yazi.enable && config.programs.fish.enable) {
    y = {
      body = ''
        set tmp (mktemp -t "yazi-cwd.XXXXX")
        yazi $argv --cwd-file="$tmp"
        if set cwd (env cat -- "$tmp"); and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
          builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
      '';
    };
  };

  programs.yazi = let
    getPlugin = src: pluginName: {${pluginName} = src + "/${pluginName}.yazi";};
  in {
    enable = true;
    # The flake builds from its own nixpkgs, which throws on x86_64-darwin (Nixpkgs 26.11+)
    package =
      if hostPlatform.isDarwin && hostPlatform.isx86_64
      then pkgs.yazi
      else inputs.yazi.packages.${hostPlatform.system}.yazi;

    enableFishIntegration = false;
    enableZshIntegration = false;
    enableBashIntegration = false;
    enableNushellIntegration = false;
    shellWrapperName = "y";

    initLua = ./init.lua;
    settings = import ./_yazi.nix {inherit pkgs lib config hostPlatform;};
    keymap = import ./_keymap.nix;
    theme = {
      flavor = {
        dark = "dracula";
      };
    };
    flavors = let
      officialFlavors = pkgs.fetchFromGitHub {
        owner = "yazi-rs";
        repo = "flavors";
        rev = "9511cb09cadcbf57e39a46b06a52d00957177175";
        hash = "sha256-3RR8mi7CcVMDMitdTdaonFmfAIkeOzWK/CVKQmomIhE=";
      };
    in
      getPlugin officialFlavors "dracula";
    plugins = let
      getOfficialPlugin = getPlugin inputs.yazi-plugins;
    in
      lib.attrsets.mergeAttrsList [
        (getOfficialPlugin "git")
        (getOfficialPlugin "smart-enter")
        (getOfficialPlugin "full-border")
        (getOfficialPlugin "diff")
        (getOfficialPlugin "chmod")
        (getOfficialPlugin "smart-filter")
        (getOfficialPlugin "mount")
        (getOfficialPlugin "toggle-pane")
        (getOfficialPlugin "piper")
        {
          ouch = pkgs.fetchFromGitHub {
            owner = "ndtoan96";
            repo = "ouch.yazi";
            rev = "406ce6c13ec3a18d4872b8f64b62f4a530759b2c";
            hash = "sha256-14x/bD0aD9hXONaqQD8Dt7rLBCMq7bkVLH6uCPOQ0C8=";
          };
        }
      ];
  };
}
