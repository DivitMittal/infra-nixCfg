{
  inputs,
  config,
  ...
}: let
  secretsPath = inputs.infra-nixCfg-secrets + "/secrets";
  mkSecret = path: {file = secretsPath + "/${path}";};
in {
  imports = [inputs.ragenix.homeManagerModules.default];

  age.identityPaths = ["${config.home.homeDirectory}/.ssh/agenix/id_ed25519"];
  age.secretsDir = "${config.xdg.configHome}/agenix";

  age.secrets = {
    "api/github.txt" = mkSecret "api/github.age";
    "github/general.txt" = mkSecret "github/general.age";
    "weechat/sec.conf" = mkSecret "weechat/sec.conf.age";
    "nix.conf" = mkSecret "nix.conf.age";
    "id_passage" = mkSecret "passage.age";
    "google/client_id.age" = mkSecret "google/client_id.age";
    "google/client_secret.age" = mkSecret "google/client_secret.age";
  };
}
