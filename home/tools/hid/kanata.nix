{inputs, ...}: {
  imports = [inputs.TLTR.homeManagerModules.default];

  programs.tltr.enable = true;
}
