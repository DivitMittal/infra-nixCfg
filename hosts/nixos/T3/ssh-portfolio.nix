# `ssh divit@qezta.com`: the Qezta/ssh terminal portfolio as a k3s workload.
# The image is built by Nix and preloaded into k3s, so no registry is needed.
{
  inputs,
  pkgs,
  ...
}: let
  namespace = "qezta-ssh";
  name = "ssh-portfolio";
  labels."app.kubernetes.io/name" = name;
  metadata = {
    inherit name namespace labels;
  };

  image = inputs.qezta-ssh.packages.${pkgs.stdenv.hostPlatform.system}.image;
  # The tag is the image's content hash, so every real change edits the
  # Deployment and rolls out a new pod.
  imageRef = "${image.imageName}:${image.imageTag}";

  # Within k3s's default NodePort range (30000-32767), so port 22 stays free
  # for T3's own sshd. Public access needs a router forward from WAN :22 to
  # T3:30022, which is deliberately not declared here.
  nodePort = 30022;
  containerPort = 23234;
in {
  services.k3s.images = [image];
  # k3s imports preloaded images when it starts. The tarball's file name never
  # changes between versions, so restart k3s whenever the image does; running
  # pods survive a k3s restart.
  systemd.services.k3s.restartTriggers = [image];

  services.k3s.manifests.ssh-portfolio.content = [
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    }
    {
      # The server's host key: clients pin it in known_hosts, so it must survive
      # pod replacement. The server generates it on first start.
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = metadata // {name = "host-key";};
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "local-path";
        resources.requests.storage = "16Mi";
      };
    }
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      inherit metadata;
      spec = {
        replicas = 1;
        # Single ReadWriteOnce volume: never run two pods during a rollout.
        strategy.type = "Recreate";
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            automountServiceAccountToken = false;
            enableServiceLinks = false;
            # The image only exists in T3's containerd, and the host key lives
            # on T3's local-path volume.
            nodeSelector = {
              "kubernetes.io/hostname" = "t3";
              "homelab-role" = "services";
            };
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 65532;
              runAsGroup = 65532;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = [
              {
                inherit name;
                image = imageRef;
                imagePullPolicy = "Never";
                env = [
                  {
                    name = "SSH_PORT";
                    value = toString containerPort;
                  }
                ];
                ports = [
                  {
                    name = "ssh";
                    inherit containerPort;
                  }
                ];
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                };
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "32Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "128Mi";
                  };
                };
                volumeMounts = [
                  {
                    name = "host-key";
                    mountPath = "/data";
                  }
                ];
                readinessProbe = {
                  tcpSocket.port = "ssh";
                  periodSeconds = 10;
                };
                livenessProbe = {
                  tcpSocket.port = "ssh";
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                };
              }
            ];
            volumes = [
              {
                name = "host-key";
                persistentVolumeClaim.claimName = "host-key";
              }
            ];
          };
        };
      };
    }
    {
      apiVersion = "v1";
      kind = "Service";
      inherit metadata;
      spec = {
        type = "NodePort";
        # Keep real client addresses in the server's connection log; the pod
        # only ever runs on T3, the advertised endpoint.
        externalTrafficPolicy = "Local";
        selector = labels;
        ports = [
          {
            name = "ssh";
            port = 22;
            targetPort = "ssh";
            inherit nodePort;
          }
        ];
      };
    }
  ];

  networking.firewall.allowedTCPPorts = [nodePort];

  topology.self.services.ssh-portfolio = {
    name = "SSH portfolio";
    info = "ssh -p ${toString nodePort} divit@T3.lan";
  };
}
