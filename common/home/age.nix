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
    "github/general.txt" = mkSecret "forge/github/general.age";
    "weechat/sec.conf" = mkSecret "comms/weechat.sec.conf.age";
    "nix.conf" = mkSecret "nix/nix.conf.age";
    "id_passage" = mkSecret "passage.age";
    "google/client_id.age" = mkSecret "comms/email/client_id.age";
    "google/client_secret.age" = mkSecret "comms/email/client_secret.age";
    ## Shared credential store read by nvchecker/nvfetcher (Python's netrc
    ## ignores $NETRC, so it must live at ~/.netrc), git (via libcurl), wget,
    ## aria2, yt-dlp `--netrc` and Python requests. Add hosts with
    ## `agenix -e netrc.age` in infra-nixCfg-secrets; agenix's default 0400
    ## mode satisfies Python's "no group/other access" check.
    "netrc" =
      mkSecret "netrc.age"
      // {path = "${config.home.homeDirectory}/.netrc";};
  };
}
