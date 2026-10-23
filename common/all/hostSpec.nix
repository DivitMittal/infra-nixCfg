{inputs, ...}: {
  imports = [inputs.infra-nixCfg-secrets.modules.hostSpec];

  hostSpec = {
    inherit (inputs.infra-nixCfg-secrets.user) username userFullName handle email;
  };
}
