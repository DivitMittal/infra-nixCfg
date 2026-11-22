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
  vcsModule = "${inputs.ai-nixCfg}/config/home/cli/vcs.nix";
  upstream = inputs.ai-nixCfg.inputs.aicommit2.packages.x86_64-linux.default;
  legacyPkgs = import inputs.aicommit2-build-nixpkgs {
    system = "x86_64-linux";
  };
  currentHook = upstream.pnpmDeps.pnpm.configHook;
  isPnpmHook = input:
    (input.drvPath or null)
    == currentHook.drvPath
    || (input.name or "") == "pnpm-config-hook";
  fixed = upstream.overrideAttrs (
    old:
      assert lib.assertMsg
      (builtins.length (builtins.filter isPnpmHook old.nativeBuildInputs) == 1)
      "aicommit2: expected exactly one pnpm configure hook to replace"; {
        # The upstream hash was verified with its locked pnpm 10.13.1 and
        # raw-store fetcher. Root nixpkgs' pnpm 11 uses a different layout.
        pnpmDeps = legacyPkgs.pnpm.fetchDeps {
          inherit (old) pname version src;
          inherit (old.pnpmDeps) fetcherVersion;
          hash = old.pnpmDeps.outputHash;
        };

        # The offline install must consume the same store format as the
        # fetcher. Keep Node.js and every other upstream native input.
        nativeBuildInputs =
          map
          (input:
            if isPnpmHook input
            then legacyPkgs.pnpm.configHook
            else input)
          old.nativeBuildInputs;
      }
  );
  vcs = import vcsModule {
    inherit lib pkgs;
    inherit (inputs) ai-nixCfg;
  };
  codexSetup = import "${inputs.ai-nixCfg}/config/home/coding/codex/setup.nix" {
    inherit config lib pkgs;
    customLib =
      customLib
      // {
        # Bare Bunx resolution exited silently on fresh compute-node caches;
        # the explicit tag resolved the package correctly on T3. Keep the
        # upstream latest-version policy, wrapper metadata and CODEX_HOME.
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
  # from PATH. Declare the hook's binary dependency instead of relying on a
  # login shell environment, so later steps (including user services) run.
  home.extraActivationPath = lib.optionals (enabled && config.programs.herdr.enable) [config.programs.herdr.package];

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
