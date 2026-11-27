# One LAN-wide CLIProxyAPI for every host. L1 keeps credentials and can run
# the same binary on demand, but it is no longer an always-on service.
#
# OAuth state stays in /var/lib/cliproxyapi/auth. The management hash and
# lappkart key stay in /var/lib/cliproxyapi/secrets. Neither belongs in git.
{
  inputs,
  pkgs,
  ...
}: let
  port = 8317;
  stateDir = "/var/lib/cliproxyapi";
  authDir = "${stateDir}/auth";
  secretDir = "${stateDir}/secrets";
  configFile = "${stateDir}/config.yaml";
  package = inputs.ai-nixCfg.packages.${pkgs.stdenvNoCC.hostPlatform.system}.cliproxyapi-plus;
  localApiKey = "cliproxyapi-lan";

  configTemplate = (pkgs.formats.yaml {}).generate "cliproxyapi.yaml" {
    config-version = 8;
    quota-exceeded = {
      switch-project = true;
      switch-preview-model = true;
    };
    routing = {
      strategy = "round-robin";
      session-affinity = false;
      session-affinity-ttl = "1h";
      cooldown.disable-cooling = false;
      retry.request-retry = 0;
    };
    access.api-keys = [localApiKey];
    management = {
      allow-remote = true;
      disable-control-panel = false;
    };
    observability = {
      logs = {
        request-log = false;
        debug = false;
        logging-to-file = false;
      };
      usage = {
        usage-statistics-enabled = true;
        redis-usage-queue-retention-seconds = 60;
      };
    };
    server = {
      host = "0.0.0.0";
      inherit port;
      discovery = {
        service-type = "_ai-gateway._tcp";
        subtypes = [
          "_chat-completions"
          "_responses"
          "_messages"
          "_generate-content"
          "_interactions"
        ];
      };
    };
    credentials = {
      concurrency = {
        cpa-heartbeat-timeout = "3s";
        cpa-cancel-bound = "5s";
        reclaim-grace = "5s";
        cleanup-interval = "5s";
        release-flush-interval = "250ms";
        release-max-backoff = "2s";
        busy-retry-min = "250ms";
        busy-retry-max = "1s";
        max-limit = 1000000;
      };
      in-flight = {
        snapshot-interval = "2s";
        stale-after = "10s";
        max-part-bytes = 262144;
        max-part-count = 64;
        max-revision-bytes = 16777216;
        max-aggregate-groups = 100000;
        max-details = 10000;
        max-string-bytes = 256;
        staging-retention = "1m";
      };
    };
    oauth = {
      auth-dir = authDir;
      model-maps.claude = [
        {
          name = "claude-opus-5-5";
          alias = "claude-opus-5-5";
        }
      ];
      providers.aistudio.ws-auth = true;
      model-alias = {
        github-copilot = [
          {
            name = "claude-opus-5.5";
            alias = "claude-opus-5-5";
            fork = true;
          }
          {
            name = "claude-haiku-4.5";
            alias = "claude-haiku-4-5";
            fork = true;
          }
          {
            name = "claude-opus-4.1";
            alias = "claude-opus-4-1";
            fork = true;
          }
          {
            name = "claude-opus-4.5";
            alias = "claude-opus-4-5";
            fork = true;
          }
          {
            name = "claude-opus-4.6";
            alias = "claude-opus-4-6";
            fork = true;
          }
          {
            name = "claude-sonnet-4.5";
            alias = "claude-sonnet-4-5";
            fork = true;
          }
          {
            name = "claude-sonnet-4.6";
            alias = "claude-sonnet-4-6";
            fork = true;
          }
        ];
        kiro = [
          {
            name = "kiro-claude-sonnet-4-6";
            alias = "claude-sonnet-4-6";
            fork = true;
          }
          {
            name = "kiro-claude-sonnet-4-5";
            alias = "claude-sonnet-4-5-20250929";
            fork = true;
          }
          {
            name = "kiro-claude-sonnet-4-5";
            alias = "claude-sonnet-4-5";
            fork = true;
          }
          {
            name = "kiro-claude-sonnet-4";
            alias = "claude-sonnet-4-20250514";
            fork = true;
          }
          {
            name = "kiro-claude-sonnet-4";
            alias = "claude-sonnet-4";
            fork = true;
          }
          {
            name = "kiro-claude-opus-4-7";
            alias = "claude-opus-4-7";
            fork = true;
          }
          {
            name = "kiro-claude-opus-4-6";
            alias = "claude-opus-4-6";
            fork = true;
          }
          {
            name = "kiro-claude-opus-4-5";
            alias = "claude-opus-4-5-20251101";
            fork = true;
          }
          {
            name = "kiro-claude-opus-4-5";
            alias = "claude-opus-4-5";
            fork = true;
          }
          {
            name = "kiro-claude-haiku-4-5";
            alias = "claude-haiku-4-5-20251001";
            fork = true;
          }
          {
            name = "kiro-claude-haiku-4-5";
            alias = "claude-haiku-4-5";
            fork = true;
          }
        ];
      };
    };
    openai-compatibility = [
      {
        name = "z-ai";
        base-url = "https://api.z.ai/api/paas/v4";
        models = [
          {
            name = "glm-4.5";
            alias = "glm-4.5";
          }
          {
            name = "glm-4.6";
            alias = "glm-4.6";
          }
        ];
      }
      {
        name = "minimax";
        base-url = "https://api.minimax.io/v1";
        models = [
          {
            name = "MiniMax-M3";
            alias = "minimax-M3";
          }
        ];
      }
      {
        name = "openrouter";
        base-url = "https://openrouter.ai/api/v1";
        models = [];
      }
    ];
    claude-api-key = [
      {
        name = "lappkart";
        base-url = "https://theclaudeapi.com";
        models = [
          {
            name = "claude-opus-5-5";
            alias = "lappkart-opus-5-5";
          }
          {
            name = "claude-fable-5-2";
            alias = "lappkart-fable-5-2";
          }
        ];
      }
    ];
  };

  # Declarative settings win, while dashboard-added named providers and secret
  # files survive activation. Secret values are inserted only at runtime.
  mergeConfig = pkgs.writeScript "cliproxyapi-merge-config" ''
    #!${pkgs.python3.withPackages (ps: [ps.pyyaml])}/bin/python
    import os
    import pathlib
    import tempfile

    import yaml


    def read_yaml(path):
        if not path.exists() or not path.read_text().strip():
            return {}
        data = yaml.safe_load(path.read_text())
        if not isinstance(data, dict):
            raise SystemExit(f"{path} is not a YAML mapping")
        return data


    def named(value):
        return isinstance(value, list) and all(isinstance(item, dict) and "name" in item for item in value)


    def merge(dynamic, static):
        result = dict(dynamic)
        for key, value in static.items():
            current = result.get(key)
            if isinstance(value, dict) and isinstance(current, dict):
                result[key] = merge(current, value)
            elif named(value) and named(current):
                current_by_name = {item["name"]: item for item in current}
                static_names = {item["name"] for item in value}
                result[key] = [merge(current_by_name.get(item["name"], {}), item) for item in value] + [
                    item for item in current if item["name"] not in static_names
                ]
            else:
                result[key] = value
        return result


    def secret(path):
        try:
            value = path.read_text().strip()
        except FileNotFoundError:
            return ""
        if len(value.splitlines()) != 1:
            raise SystemExit(f"{path} must contain exactly one line")
        return value


    destination = pathlib.Path(os.environ["CLIPROXYAPI_CONFIG"])
    secrets = pathlib.Path(os.environ["CLIPROXYAPI_SECRETS"])
    destination.parent.mkdir(parents=True, exist_ok=True)
    merged = merge(read_yaml(destination), read_yaml(pathlib.Path(os.environ["CLIPROXYAPI_TEMPLATE"])))

    management_key = secret(secrets / "management-secret-key")
    if management_key:
        merged.setdefault("management", {})["secret-key"] = management_key

    provider_key = secret(secrets / "lappkart-api-key")
    if provider_key:
        for provider in merged.get("claude-api-key", []):
            if provider.get("name") == "lappkart":
                provider["api-key"] = provider_key

    with tempfile.NamedTemporaryFile("w", dir=destination.parent, delete=False) as output:
        temporary = pathlib.Path(output.name)
        try:
            output.write(yaml.safe_dump(merged, sort_keys=False))
            output.flush()
            os.fsync(output.fileno())
            os.chmod(temporary, 0o600)
            os.chown(temporary, os.getuid(), os.getgid())
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
  '';
in {
  environment.systemPackages = [package];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 div users - -"
    "d ${authDir} 0700 div users - -"
    "d ${secretDir} 0700 div users - -"
    "z ${configFile} 0600 div users - -"
  ];

  systemd.services.cliproxyapi-config = {
    description = "Merge declarative CLIProxyAPI settings without dropping runtime state";
    wantedBy = ["multi-user.target"];
    before = ["cliproxyapi.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "div";
      Group = "users";
      StateDirectory = "cliproxyapi";
    };
    environment = {
      CLIPROXYAPI_CONFIG = configFile;
      CLIPROXYAPI_TEMPLATE = configTemplate;
      CLIPROXYAPI_SECRETS = secretDir;
    };
    script = "exec ${mergeConfig}";
  };

  systemd.services.cliproxyapi = {
    description = "LAN-wide CLIProxyAPI";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target" "cliproxyapi-config.service"];
    after = ["network-online.target" "cliproxyapi-config.service"];
    serviceConfig = {
      ExecStart = "${package}/bin/cli-proxy-api-plus -config ${configFile}";
      WorkingDirectory = stateDir;
      User = "div";
      Group = "users";
      Restart = "on-failure";
      RestartSec = 2;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [stateDir];
    };
  };

  networking.firewall.interfaces.enp2s0f0.allowedTCPPorts = [port];

  topology.self.services.cliproxyapi = {
    name = "CLIProxyAPI";
    info = "http://192.168.2.8:${toString port}";
  };
}
