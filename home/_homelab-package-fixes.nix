{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  enabled =
    builtins.elem config.hostSpec.hostName ["T2" "T3"]
    && pkgs.stdenvNoCC.hostPlatform.system == "x86_64-linux";
  vcsModule = "${inputs.ai-nixCfg}/config/home/cli/vcs.nix";
  upstream = inputs.ai-nixCfg.inputs.aicommit2.packages.x86_64-linux.default;
  fixed = upstream.overrideAttrs (old: {
    pnpmDeps = old.pnpmDeps.overrideAttrs (deps: {
      # pnpm 11's 60-second AbortSignal deadline also covers large response
      # bodies. Its TimeoutError has code 23; retries can leave optional
      # Copilot packages absent and cause a later ENOENT during linking.
      preInstall =
        (deps.preInstall or "")
        + ''
          export pnpm_config_fetch_timeout=600000
          export pnpm_config_network_concurrency=4
        '';
    });
  });
  vcs = import vcsModule {
    inherit lib pkgs;
    inherit (inputs) ai-nixCfg;
  };
in {
  # ai-nixCfg selects its flake package directly, bypassing pkgs overlays.
  # Reuse its package list so geminicommit and future additions survive.
  disabledModules = [vcsModule];
  home.packages =
    map
    (package:
      if enabled && package.drvPath == upstream.drvPath
      then fixed
      else package)
    vcs.home.packages;
}
