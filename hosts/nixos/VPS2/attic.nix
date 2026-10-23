{inputs, ...}: let
  # R2 bucket/endpoint provisioned by flake/terranix.nix (cloudflare_r2_bucket.attic_cache).
  # Fill in once that config has actually been applied — see flake/terranix.nix for the bucket name.
  r2AccountId = "REPLACE_WITH_CLOUDFLARE_ACCOUNT_ID";
  r2Bucket = "os-nixcfg-attic";
in {
  imports = [inputs.attic.nixosModules.atticd];

  # Not exposed publicly yet (see conversation: DNS/Cloudflare proxying deferred until
  # real credentials + a domain are wired up). Bound to loopback only for now; reachable
  # for manual testing via `ssh -L 8080:localhost:8080 VPS2`.
  services.atticd = {
    enable = true;

    # TODO: once infra-nixCfg-secrets/secrets/attic/env.age exists (containing
    # ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
    # for the R2 bucket below), replace this literal with:
    #   age.secrets."attic/env".file = (inputs.infra-nixCfg-secrets + "/secrets") + "/attic/env.age";
    #   services.atticd.environmentFile = config.age.secrets."attic/env".path;
    # A literal path is used here instead so evaluation doesn't depend on that
    # not-yet-created encrypted file — it matches where agenix would put it anyway.
    environmentFile = "/run/agenix/attic/env";

    settings = {
      listen = "127.0.0.1:8080";

      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";

      storage = {
        type = "s3";
        region = "auto";
        bucket = r2Bucket;
        endpoint = "https://${r2AccountId}.r2.cloudflarestorage.com";
      };

      chunking = {
        nar-size-threshold = 65536;
        min-size = 16384;
        avg-size = 65536;
        max-size = 262144;
      };

      compression.type = "zstd";

      garbage-collection.interval = "12 hours";
    };
  };
}
