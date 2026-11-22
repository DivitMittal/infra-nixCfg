{inputs, ...}: {
  imports = [
    inputs.firefox-nixCfg.homeManagerModules.default
  ];

  programs.firefox-nixCfg = {
    enable = true;
    enableTridactyl = true;
    enableWebHID = true;
  };
}
