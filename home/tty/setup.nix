{
  hostPlatform,
  inputs,
  lib,
  ...
}: {
  disabledModules =
    [
      "${inputs.term-nixCfg}/config/home/tty/multiplexers/herdr.nix"
      "${inputs.term-nixCfg}/config/home/tty/multiplexers/kolu.nix"
      "${inputs.term-nixCfg.inputs.kolu}/nix/home/module.nix"
    ]
    ++ lib.optionals hostPlatform.isDarwin [
      "${inputs.ai-nixCfg}/config/home/browser.nix"
      "${inputs.ai-nixCfg}/config/home/mcp.nix"
    ];

  imports = [
    inputs.ai-nixCfg.homeManagerConfigurations.Cfg
    inputs.term-nixCfg.homeManagerConfigurations.tty
    ./cliproxyapi.nix
  ];

  aiNixCfg.voice.installDarwinApps = false;

  services.kolu = {
    tuiPackage = lib.mkForce inputs.ai-nixCfg.inputs.kolu.packages.${hostPlatform.system}.kaval-tui;
    padiTuiPackage = lib.mkForce inputs.ai-nixCfg.inputs.kolu.packages.${hostPlatform.system}.padi-tui;
  };
}
