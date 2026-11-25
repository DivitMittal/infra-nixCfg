{
  hostPlatform,
  inputs,
  lib,
  pkgs,
  ...
}: let
  legacyAi = inputs.ai-nixCfg.inputs ? aicommit2;
  aicommit2 = lib.custom.mkBunxBin "aicommit2" "aicommit2@latest";
in {
  disabledModules =
    lib.optionals hostPlatform.isDarwin [
      "${inputs.ai-nixCfg}/config/home/browser.nix"
      "${inputs.ai-nixCfg}/config/home/mcp.nix"
    ]
    ++ lib.optional legacyAi "${inputs.ai-nixCfg}/config/home/cli/vcs.nix";

  imports = [
    inputs.ai-nixCfg.homeManagerConfigurations.Cfg
    inputs.term-nixCfg.homeManagerConfigurations.tty
  ];

  # Match the migrated AI module while the flake still pins the older revision.
  home.packages = lib.optionals legacyAi [
    pkgs.geminicommit
    aicommit2
    (pkgs.writeShellScriptBin "aic2" ''exec ${lib.getExe aicommit2} "$@"'')
  ];

  services.kolu.enable = lib.mkIf (hostPlatform.isDarwin && hostPlatform.isx86_64) (lib.mkForce false);
}
