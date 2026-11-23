{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  lanAddress = "192.168.2.3";
  dir = "/var/lib/home-assistant";
  secret = name: inputs.infra-nixCfg-secrets + "/secrets/homelab/${name}.age";
  credentials = ["mqtt-home-assistant" "mqtt-wled-desk"];
  enabled = lib.all (name: builtins.pathExists (secret name)) credentials;
  configuration = pkgs.writeText "home-assistant.yaml" ''
    default_config:
    http:
      server_host: ${lanAddress}
    automation: !include automations.yaml
    script: !include scripts.yaml
    scene: !include scenes.yaml
  '';
in {
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = enabled || !(lib.any (name: builtins.pathExists (secret name)) credentials);
          message = "T1 Home Assistant requires both encrypted MQTT credential files.";
        }
      ];
    }
    (lib.mkIf enabled {
      age.secrets = lib.genAttrs credentials (name: {file = secret name;});

      virtualisation = {
        podman.enable = true;
        oci-containers = {
          backend = "podman";
          containers.home-assistant = {
            # Home Assistant 2026.11.2.
            image = "ghcr.io/home-assistant/home-assistant@sha256:493a07e8f6530fc640223f4a0a5248f20a61ca2f718bb1d31efbf08a2c5ea28f";
            volumes = [
              "${dir}:/config"
              "${configuration}:/config/configuration.yaml:ro"
            ];
            # WLED discovery needs LAN multicast. Bound the container so routing
            # retains CPU and memory headroom under sustained assistant load.
            extraOptions = ["--network=host" "--cpus=1" "--memory=2g"];
            environment.TZ = "Asia/Kolkata";
          };
        };
      };
      systemd.tmpfiles.rules = [
        "d ${dir} 0700 root root -"
        "f ${dir}/automations.yaml 0600 root root - []"
        "f ${dir}/scripts.yaml 0600 root root - {}"
        "f ${dir}/scenes.yaml 0600 root root - []"
      ];

      services.mosquitto = {
        enable = true;
        persistence = true;
        listeners = [
          {
            address = lanAddress;
            settings.allow_anonymous = false;
            users = {
              home-assistant = {
                passwordFile = config.age.secrets.mqtt-home-assistant.path; # ggignore: runtime path, not a password
                acl = ["read homeassistant/sensor/+/#" "read wled/desk/#" "write homeassistant/status"];
              };
              wled-desk = {
                passwordFile = config.age.secrets.mqtt-wled-desk.path; # ggignore: runtime path, not a password
                acl = ["readwrite wled/desk/#" "write homeassistant/sensor/+/#"];
              };
            };
          }
        ];
      };
      systemd.services.mosquitto = {
        after = ["network-online.target"];
        wants = ["network-online.target"];
      };
    })
  ];
}
