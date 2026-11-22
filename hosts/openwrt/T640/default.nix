{
  inputs,
  # "dmz" (R0 DMZ-forwards to a static WAN) or "pppoe" (R0 bridged, two
  # PPPoE lines + mwan3). See modules/network.nix.
  wanMode ? "dmz",
  ...
}: {
  _module.args = {
    inherit wanMode;
    # MACs, SSID etc. from the private infra-nixCfg-secrets.
    inherit (inputs.infra-nixCfg-secrets) homelab;
  };

  imports = [(inputs.import-tree ./modules)];
}
