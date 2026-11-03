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

  services.kolu.enable = lib.mkIf (hostPlatform.isDarwin && hostPlatform.isx86_64) (lib.mkForce false);
}
