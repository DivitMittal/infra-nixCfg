{
  inputs,
  hostPlatform,
  ...
}: {
  imports = [inputs.quant-nixCfg.homeManagerModules.ibkr];

  ## IBKR Desktop (Interactive Brokers), installed as the `ibkr` Homebrew cask
  programs.ibkr.enable = hostPlatform.isDarwin;
}
