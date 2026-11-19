# Public manifests only: credentials must be injected separately at runtime.
_: let
  namespace = "rsshub";
  labels = name: {"app.kubernetes.io/name" = name;};
  metadata = name: {
    inherit name namespace;
    labels = labels name;
  };
  service = name: port: overrides: {
    apiVersion = "v1";
    kind = "Service";
    metadata = metadata name;
    spec =
      {
        selector = labels name;
        ports = [
          {
            inherit port;
            targetPort = port;
          }
        ];
      }
      // overrides;
  };
  deployment = name: container: podOptions: {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = metadata name;
    spec = {
      replicas = 1;
      strategy.type = "RollingUpdate";
      selector.matchLabels = labels name;
      template = {
        metadata.labels = labels name;
        spec =
          {
            automountServiceAccountToken = false;
            containers = [container];
          }
          // podOptions;
      };
    };
  };
  rsshub =
    deployment "rsshub" {
      name = "rsshub";
      # Upstream release v2026.11.16-8658.b4990a8, commit-specific image tag.
      image = "ghcr.io/diygod/rsshub:b4990a809138010275532fbab0efe8d55e2dc779";
      ports = [
        {
          name = "http";
          containerPort = 1200;
        }
      ];
      env = builtins.map (name: {
        inherit name;
        value =
          {
            NODE_ENV = "production";
            PORT = "1200";
            LISTEN_INADDR_ANY = "true";
            # One RSSHub replica needs no separate cache service or persistent disk.
            CACHE_TYPE = "memory";
            MEMORY_MAX = "256";
            CACHE_EXPIRE = "300";
            CACHE_CONTENT_EXPIRE = "3600";
          }.${
            name
          };
      }) ["NODE_ENV" "PORT" "LISTEN_INADDR_ANY" "CACHE_TYPE" "MEMORY_MAX" "CACHE_EXPIRE" "CACHE_CONTENT_EXPIRE"];
      resources = {
        requests = {
          cpu = "100m";
          memory = "256Mi";
        };
        limits = {
          cpu = "1000m";
          memory = "768Mi";
        };
      };
      readinessProbe = {
        httpGet = {
          path = "/";
          port = "http";
        };
        periodSeconds = 10;
      };
      startupProbe = {
        httpGet = {
          path = "/";
          port = "http";
        };
        periodSeconds = 5;
        failureThreshold = 60;
      };
      livenessProbe = {
        httpGet = {
          path = "/";
          port = "http";
        };
        periodSeconds = 30;
      };
    } {
      # Prefer the services node, but allow spare worker capacity on T2.
      affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
        {
          weight = 100;
          preference.matchExpressions = [
            {
              key = "homelab-role";
              operator = "In";
              values = ["services"];
            }
          ];
        }
      ];
    };
in {
  # Prevent a native instance from surviving the migration alongside the pods.
  services.rsshub.enable = false;
  services.k3s.manifests.rsshub.content = [
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    }
    rsshub
    (service "rsshub" 1200 {
      type = "NodePort";
      # Preserve the T3 endpoint even when RSSHub is scheduled on T2.
      externalTrafficPolicy = "Cluster";
      ports = [
        {
          port = 1200;
          targetPort = "http";
          nodePort = 31200;
        }
      ];
    })
  ];

  topology.self.services.rsshub = {
    name = "RSSHub";
    info = "http://T3.lan:31200";
  };
}
