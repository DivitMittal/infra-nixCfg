# Self-hosted attic binary cache for the home lab and CI, replacing Cachix
# (whose free tier caps at 5 GiB). Builders (T2/T3, CI) push to the `infra`
# cache; home-lab hosts substitute from it (hosts/nixos/_homelab/base.nix).
#
# Reached on the LAN at http://192.168.2.8:8080 (router reservation, see
# hosts/openwrt/T640). CI reaches it through T1's Tailscale subnet route.
# Storage is local for now; move `storage.path` to the HDD once one is
# attached and declared.
{
  config,
  inputs,
  ...
}: {
  age.secrets.attic-server-env = {
    file = inputs.infra-nixCfg-secrets + "/secrets/homelab/attic-server.env.age";
    mode = "0400";
  };

  services.atticd = {
    enable = true;
    # ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64: signs the push/pull tokens.
    environmentFile = config.age.secrets.attic-server-env.path;
    settings = {
      listen = "0.0.0.0:8080";
      api-endpoint = "http://192.168.2.8:8080/";
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      storage = {
        type = "local";
        path = "/var/lib/atticd/storage";
      };
      chunking = {
        nar-size-threshold = 65536;
        min-size = 16384;
        avg-size = 65536;
        max-size = 262144;
      };
      compression.type = "zstd";
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "3 months";
      };
    };
  };
}
