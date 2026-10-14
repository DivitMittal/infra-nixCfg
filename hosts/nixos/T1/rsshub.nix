# RSSHub (https://docs.rsshub.app) — RSS feed generator for sites that don't
# publish feeds, served to the home LAN/tailnet. Uses the upstream nixpkgs
# module (nixos/modules/services/web-apps/rsshub.nix): DynamicUser-sandboxed
# systemd unit, plus a dedicated local Redis instance (`redis-rsshub`) as the
# route cache instead of RSSHub's default in-process memory cache, so cached
# feeds survive service restarts.
#
# Only the host side is exposed: the WAN NIC is macvtap-passed straight into
# the router VM (router-vm.nix), so binding on all host addresses reaches the
# LAN/tailnet without touching the ISP-facing link.
_: {
  services.rsshub = {
    enable = true;
    # Firewall is off by default (common/hosts/nixos/networking.nix); this only
    # matters if T1 ever turns it on.
    openFirewall = true;
    redis.enable = true;
    settings = {
      LISTEN_INADDR_ANY = true;
      PORT = 1200;
      # Route-level cache TTLs (seconds) — RSSHub defaults, made explicit.
      CACHE_EXPIRE = "300";
      CACHE_CONTENT_EXPIRE = "3600";
    };
    # Per-route credentials (e.g. GITHUB_ACCESS_TOKEN, TWITTER_AUTH_TOKEN) go
    # in an agenix-decrypted env file once needed:
    # secretFiles = [config.age.secrets."rsshub/env".path];
  };

  topology.self.services.rsshub = {
    name = "RSSHub";
    info = "http://T1:1200";
  };
}
