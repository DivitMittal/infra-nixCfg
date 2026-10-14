## Alertmanager routing.
##
## - critical → ntfy (immediate) + Discord (immediate)
## - warning  → Discord only, grouped daily
##
## Notifier secrets are read from env vars sourced from `secrets.alertmanagerEnvFile`.
## We use Alertmanager's webhook receiver (no built-in ntfy/discord support), so the
## URL itself is the secret — interpolated via `${"$"}{NTFY_TOPIC_URL}` etc.
_: {
  global = {
    resolve_timeout = "5m";
  };

  route = {
    receiver = "default";
    group_by = ["alertname" "host"];
    group_wait = "30s";
    group_interval = "5m";
    repeat_interval = "12h";
    routes = [
      {
        matchers = ["severity=critical"];
        receiver = "critical";
        group_wait = "10s";
        repeat_interval = "1h";
      }
      {
        matchers = ["severity=warning"];
        receiver = "warning";
        group_interval = "24h";
        repeat_interval = "24h";
      }
    ];
  };

  receivers = [
    {
      name = "default";
      webhook_configs = [
        {
          url = "\${NTFY_TOPIC_URL:-http://127.0.0.1:65535/dev-null}";
          send_resolved = true;
        }
      ];
    }
    {
      name = "critical";
      webhook_configs = [
        {
          url = "\${NTFY_TOPIC_URL:-http://127.0.0.1:65535/dev-null}";
          send_resolved = true;
          http_config.basic_auth = {};
        }
        {
          url = "\${DISCORD_WEBHOOK:-http://127.0.0.1:65535/dev-null}";
          send_resolved = true;
        }
      ];
    }
    {
      name = "warning";
      webhook_configs = [
        {
          url = "\${DISCORD_WEBHOOK:-http://127.0.0.1:65535/dev-null}";
          send_resolved = false;
        }
      ];
    }
  ];

  inhibit_rules = [
    {
      ## A host that's down should not also page on its derived alerts.
      source_matchers = ["alertname=HostDown"];
      target_matchers = ["severity=~warning|critical"];
      equal = ["host"];
    }
  ];
}
