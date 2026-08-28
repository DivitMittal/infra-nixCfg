{
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

  ## Wispr Flow dictation
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["wispr-flow"];
}
