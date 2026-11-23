# Direct tailnet access to the cache without making T3 a subnet router.
{config, ...}: {
  services.tailscale = {
    enable = true;
    extraSetFlags = ["--accept-dns=false" "--accept-routes=false"];
  };
  networking.networkmanager.unmanaged = ["interface-name:${config.services.tailscale.interfaceName}"];
}
