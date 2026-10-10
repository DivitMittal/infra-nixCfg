{
  pkgs,
  hostPlatform,
  inputs,
  lib,
  ...
}: {
  disabledModules =
    [
      "${inputs.term-nixCfg}/config/home/tty/multiplexers/herdr.nix"
    ]
    ++ lib.optionals hostPlatform.isDarwin [
      "${inputs.ai-nixCfg}/config/home/browser.nix"
      "${inputs.ai-nixCfg}/config/home/mcp.nix"
    ];

  imports = [
    inputs.ai-nixCfg.homeManagerConfigurations.Cfg
    inputs.term-nixCfg.homeManagerConfigurations.tty
  ];

  aiNixCfg.voice.installDarwinApps = false;

  # kolu moved from ai-nixCfg to term-nixCfg upstream (ai-nixCfg dropped its
  # own copy 2026-07-15); term-nixCfg's own multiplexers/kolu.nix wrapper now
  # sets package/tuiPackage/padiTuiPackage, so nothing kolu-specific is needed here.

  ## Wispr Flow dictation
  home.packages = lib.optionals hostPlatform.isDarwin [pkgs.brewCasks.wispr-flow];
}
