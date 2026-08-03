{inputs, ...}: {
  imports = [
    inputs.ai-nixCfg.homeManagerConfigurations.Cfg
    inputs.term-nixCfg.homeManagerConfigurations.tty
  ];

  aiNixCfg.voice.installDarwinApps = false;
}
