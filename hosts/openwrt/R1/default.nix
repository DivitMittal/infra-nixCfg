{
  inputs,
  wanMode ? "ont",
  ...
}: {
  _module.args = {
    inherit wanMode;
    # MACs, SSID etc. from the private infra-nixCfg-secrets.
    inherit (inputs.infra-nixCfg-secrets) homelab;
  };

  imports = [(inputs.import-tree ./modules)];
}
