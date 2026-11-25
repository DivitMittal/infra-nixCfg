{
  config,
  inputs,
  lib,
  pkgs,
  customLib,
  ...
}: let
  enabled =
    builtins.elem config.hostSpec.hostName ["T2" "T3"]
    && pkgs.stdenvNoCC.hostPlatform.system == "x86_64-linux";
  codexSetup = import "${inputs.ai-nixCfg}/config/home/coding/codex/setup.nix" {
    inherit config lib pkgs;
    customLib =
      customLib
      // {
        # Older AI pins need an explicit tag to resolve on fresh Bunx caches.
        mkBunxBin = cliPkgs: name: package:
          customLib.mkBunxBin cliPkgs name (
            if package == "@openai/codex"
            then "@openai/codex@latest"
            else package
          );
      };
  };
in {
  programs.codex.package = lib.mkIf enabled (lib.mkForce codexSetup.programs.codex.package);
  # The plugin activation hook exits the whole activation if Herdr is absent
  # from PATH. Declare its binary dependency rather than relying on login PATH.
  home.extraActivationPath = lib.optionals (enabled && config.programs.herdr.enable) [config.programs.herdr.package];
}
