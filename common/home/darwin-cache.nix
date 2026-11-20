{
  config,
  inputs,
  lib,
  hostPlatform,
  ...
}: let
  endpoint = "http://192.168.2.8:8080/darwin";
  publicKey = "darwin:M23zZ3tCyh8PKSIwtRe5mrTYja5qChQAWJL6IquQTEk=";
  credentialPath = config.age.secrets.attic-darwin-pull.path;
in {
  config = lib.mkIf hostPlatform.isDarwin {
    age.secrets.attic-darwin-pull = {
      file = inputs.infra-nixCfg-secrets + "/secrets/homelab/attic-darwin-pull.age";
      path = "${config.xdg.configHome}/nix/darwin-cache.netrc";
    };

    nix.settings = {
      extra-substituters = [endpoint];
      extra-trusted-public-keys = [publicKey];
      netrc-file = credentialPath;
    };

    # The encrypted shared nix.conf optionally includes this file so cache
    # access also survives secret refreshes before the new profile is activated.
    xdg.configFile."nix/darwin-cache.conf".text = ''
      extra-substituters = ${endpoint}
      extra-trusted-public-keys = ${publicKey}
      netrc-file = ${credentialPath}
    '';
  };
}
