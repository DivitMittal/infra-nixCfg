{
  inputs,
  wanMode ? "ont",
  ...
}: {
  _module.args.wanMode = wanMode;

  imports = [(inputs.import-tree ./modules)];
}
