## Shared observability options
##
## Declared on every NixOS/Darwin host (auto-imported from common/hosts/all).
## Implementations live under:
##   - common/hosts/nixos/observability/   (server + agent)
##   - common/hosts/darwin/observability/  (agent only)
##
## Hosts opt in by setting `services.observability.role` to "server" or "agent".
{lib, ...}: let
  inherit (lib) mkOption types literalExpression;

  hostOpts = {
    options = {
      name = mkOption {
        type = types.str;
        description = "Hostname used as Prometheus instance label.";
      };
      address = mkOption {
        type = types.str;
        description = "IP or DNS name reachable by the obs-host (typically a Tailscale name).";
      };
      class = mkOption {
        type = types.enum ["nixos" "darwin" "droid"];
        description = "OS class — affects which exporters get scraped.";
      };
      labels = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Extra labels merged into scrape targets for this host.";
      };
    };
  };
in {
  options.services.observability = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Master switch for the observability subsystem on this host.";
    };

    role = mkOption {
      type = types.enum ["server" "agent" "none"];
      default = "none";
      description = ''
        "server" runs Prometheus + Grafana + Loki + Tempo + Alertmanager.
        "agent"  runs only the exporters and log shippers.
        "none"   declares options without activating anything.
      '';
    };

    serverHost = mkOption {
      type = types.str;
      default = "L2";
      description = "Hostname (must match an entry in `fleet.hosts`) that runs the server role.";
    };

    fleet.hosts = mkOption {
      type = types.listOf (types.submodule hostOpts);
      default = [];
      example = literalExpression ''
        [
          { name = "L2"; address = "l2.example.ts.net"; class = "nixos"; }
          { name = "T2"; address = "t2.example.ts.net"; class = "nixos"; }
          { name = "L1"; address = "l1.example.ts.net"; class = "darwin"; }
        ]
      '';
      description = "Static inventory of hosts scraped by the obs-host.";
    };

    ports = {
      prometheus = mkOption {
        type = types.port;
        default = 9090;
      };
      grafana = mkOption {
        type = types.port;
        default = 3000;
      };
      loki = mkOption {
        type = types.port;
        default = 3100;
      };
      tempo = mkOption {
        type = types.port;
        default = 3200;
      };
      tempoOtlpGrpc = mkOption {
        type = types.port;
        default = 4317;
      };
      tempoOtlpHttp = mkOption {
        type = types.port;
        default = 4318;
      };
      alertmanager = mkOption {
        type = types.port;
        default = 9093;
      };
      nodeExporter = mkOption {
        type = types.port;
        default = 9100;
      };
      blackboxExporter = mkOption {
        type = types.port;
        default = 9115;
      };
      alloy = mkOption {
        type = types.port;
        default = 12345;
      };
      otelCollector = mkOption {
        type = types.port;
        default = 4319;
      };
    };

    retention = {
      metrics = mkOption {
        type = types.str;
        default = "90d";
        description = "Prometheus retention.";
      };
      logs = mkOption {
        type = types.str;
        default = "30d";
        description = "Loki retention.";
      };
      traces = mkOption {
        type = types.str;
        default = "72h";
        description = "Tempo retention (traces churn fast; keep short).";
      };
    };

    secrets = {
      alertmanagerEnvFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to an env file (decrypted by agenix) containing notifier secrets:
          NTFY_TOPIC_URL, DISCORD_WEBHOOK, SMTP_PASSWORD, etc.
          Referenced by Alertmanager via `${"$"}{ENV}` interpolation.
        '';
      };
      grafanaAdminPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to a file containing the initial Grafana admin password.";
      };
    };

    alerts = {
      ntfyTopic = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://ntfy.sh/my-fleet-alerts";
        description = "ntfy.sh topic URL used as the default notifier.";
      };
      discordWebhookEnvVar = mkOption {
        type = types.str;
        default = "DISCORD_WEBHOOK";
        description = "Name of the env var (in alertmanagerEnvFile) holding a Discord webhook.";
      };
    };

    blackbox = {
      tcpTargets = mkOption {
        type = types.listOf (types.submodule {
          options = {
            address = mkOption {type = types.str;};
            port = mkOption {type = types.port;};
            description = mkOption {
              type = types.str;
              default = "";
            };
          };
        });
        default = [];
        description = "TCP probes (host + port).";
      };
      httpsCertTargets = mkOption {
        type = types.listOf types.str;
        default = [];
        example = literalExpression ''["https://example.com" "https://api.example.com"]'';
        description = "HTTPS URLs to probe for cert expiry.";
      };
      dnsTargets = mkOption {
        type = types.listOf types.str;
        default = ["example.com" "github.com"];
        description = "Hostnames to resolve from each probe location.";
      };
    };
  };
}
