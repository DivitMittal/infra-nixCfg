# Imported by the builders (T2, T3): push every new store path to the home
# lab's attic cache, so whatever one machine builds the others download.
{
  config,
  inputs,
  pkgs,
  ...
}: let
  home = "/var/lib/attic-watch-store";
in {
  age.secrets.attic-push-token = {
    file = inputs.infra-nixCfg-secrets + "/secrets/homelab/attic-push.age";
    mode = "0400";
  };

  systemd.services.attic-watch-store = {
    description = "Push new store paths to the home-lab attic cache";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    environment.HOME = home;
    serviceConfig = {
      StateDirectory = "attic-watch-store";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    # Written to a 0600 config file rather than `attic login`, which would put
    # the token on the command line.
    preStart = ''
      umask 077
      mkdir -p ${home}/.config/attic
      printf '%s\n' \
        'default-server = "homelab"' \
        '[servers.homelab]' \
        'endpoint = "http://192.168.2.8:8080/"' \
        "token = \"$(cat ${config.age.secrets.attic-push-token.path})\"" \
        > ${home}/.config/attic/config.toml
    '';
    script = "exec ${pkgs.attic-client}/bin/attic watch-store homelab:infra";
  };
}
