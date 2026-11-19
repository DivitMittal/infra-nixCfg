# Tailscale subnet router: puts the whole home LAN (192.168.2.0/24) on the
# tailnet through T1's host, so remote access survives router-image rebuilds
# and doesn't depend on anything inside the OpenWrt VM. Setup steps (auth
# key, route approval, key expiry): docs/homelab-build-cache.md.
{
  config,
  inputs,
  lib,
  ...
}: let
  lanSubnet = "192.168.2.0/24";

  # The pre-approved auth key lives in the private secrets input. Until it is
  # created, T1 still runs tailscaled with the route advertised and can be
  # joined by hand (`tailscale up`); once it exists, joining is automatic.
  authKeyRel = "/secrets/homelab/T1-tailscale.age";
  hasAuthKey = builtins.pathExists (inputs.infra-nixCfg-secrets + authKeyRel);
in {
  age.secrets = lib.mkIf hasAuthKey {
    "homelab/T1-tailscale" = {
      file = inputs.infra-nixCfg-secrets + authKeyRel;
      mode = "0400";
    };
  };

  services.tailscale = {
    enable = true;
    # Enables IP forwarding and loose reverse-path filtering for the subnet
    # route. Tailscale SNATs routed traffic by default, so LAN hosts reply to
    # T1 rather than to their default gateway (the router VM); keep that.
    useRoutingFeatures = "server";
    authKeyFile =
      if hasAuthKey
      then config.age.secrets."homelab/T1-tailscale".path
      else null;
    # `tailscale set` runs whether or not the key exists, so the route is
    # advertised either way. DNS stays on the router (192.168.2.1): MagicDNS
    # would rewrite T1's resolv.conf under networkd.
    #
    # Exit node deliberately off. To offer one later, add
    # "--advertise-exit-node" here and approve it in the admin console.
    extraSetFlags = [
      "--advertise-routes=${lanSubnet}"
      "--accept-dns=false"
    ];
  };

  # networkd is told to leave tailscale0 alone by the nixpkgs module; do the
  # same for NetworkManager, which is enabled on every NixOS host here.
  networking.networkmanager.unmanaged = ["interface-name:${config.services.tailscale.interfaceName}"];
}
