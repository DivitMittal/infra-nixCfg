{
  inputs,
  # "dmz" (R0 DMZ-forwards to a static WAN) or "pppoe" (R0 bridged, two
  # PPPoE lines + mwan3). See modules/network.nix.
  wanMode ? "dmz",
  ...
}: {
  _module.args.wanMode = wanMode;

  imports = [(inputs.import-tree ./modules)];
}
