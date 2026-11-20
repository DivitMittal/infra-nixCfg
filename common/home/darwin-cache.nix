{
  config,
  inputs,
  lib,
  hostPlatform,
  ...
}: {
  config = lib.mkIf hostPlatform.isDarwin {
    age.secrets.attic-darwin-pull = {
      file = inputs.infra-nixCfg-secrets + "/secrets/homelab/attic-darwin-pull.age";
      path = "${config.xdg.configHome}/nix/darwin-cache.netrc";
    };

    nix.settings = {
      extra-substituters = ["http://192.168.2.8:8080/darwin"];
      extra-trusted-public-keys = ["darwin:M23zZ3tCyh8PKSIwtRe5mrTYja5qChQAWJL6IquQTEk="];
      netrc-file = config.age.secrets.attic-darwin-pull.path;
    };
  };
}
