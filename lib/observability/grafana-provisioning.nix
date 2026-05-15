## Generates the data structures that get passed to `services.grafana.provision.*`.
##
## Dashboards live as static JSON under ./dashboards/ and are exposed via a
## file-based provider; reload happens on Grafana restart.
{
  cfg,
  pkgs,
  dashboardsSrc,
}: let
  inherit (cfg) ports;

  dashboardsDir = pkgs.linkFarm "observability-dashboards" [
    {
      name = "fleet-overview.json";
      path = dashboardsSrc + "/fleet-overview.json";
    }
    {
      name = "per-host.json";
      path = dashboardsSrc + "/per-host.json";
    }
    {
      name = "nix-health.json";
      path = dashboardsSrc + "/nix-health.json";
    }
    {
      name = "network-mesh.json";
      path = dashboardsSrc + "/network-mesh.json";
    }
  ];
in {
  datasources = {
    apiVersion = 1;
    datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        access = "proxy";
        url = "http://127.0.0.1:${toString ports.prometheus}";
        isDefault = true;
        editable = false;
      }
      {
        name = "Loki";
        type = "loki";
        access = "proxy";
        url = "http://127.0.0.1:${toString ports.loki}";
        editable = false;
        jsonData.derivedFields = [
          {
            datasourceName = "Tempo";
            matcherRegex = "trace_id=(\\w+)";
            name = "TraceID";
            url = "$${__value.raw}";
          }
        ];
      }
      {
        name = "Tempo";
        type = "tempo";
        access = "proxy";
        url = "http://127.0.0.1:${toString ports.tempo}";
        editable = false;
        jsonData = {
          tracesToLogsV2 = {
            datasourceUid = "loki";
            spanStartTimeShift = "-5m";
            spanEndTimeShift = "5m";
            filterByTraceID = true;
          };
          serviceMap.datasourceUid = "prometheus";
          nodeGraph.enabled = true;
        };
      }
      {
        name = "Alertmanager";
        type = "alertmanager";
        access = "proxy";
        url = "http://127.0.0.1:${toString ports.alertmanager}";
        editable = false;
        jsonData.implementation = "prometheus";
      }
    ];
  };

  dashboards = {
    apiVersion = 1;
    providers = [
      {
        name = "OS-nixCfg";
        orgId = 1;
        folder = "OS-nixCfg";
        type = "file";
        disableDeletion = true;
        editable = false;
        updateIntervalSeconds = 60;
        allowUiUpdates = false;
        options.path = "${dashboardsDir}";
      }
    ];
  };
}
