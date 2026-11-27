# Direct tailnet access to the cache without making T3 a subnet router.
{
  config,
  inputs,
  lib,
  ...
}: let
  key = inputs.infra-nixCfg-secrets + "/secrets/homelab/T3-tailscale.age";
  hasKey = builtins.pathExists key;
in {
  age.secrets."homelab/T3-tailscale" = lib.mkIf hasKey {
    file = key;
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    authKeyFile =
      if hasKey
      then config.age.secrets."homelab/T3-tailscale".path
      else null;
    extraSetFlags = ["--accept-dns=false" "--accept-routes=false"];
  };
  networking.networkmanager.unmanaged = ["interface-name:${config.services.tailscale.interfaceName}"];
}
