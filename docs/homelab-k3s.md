# Homelab k3s

T3 runs the sole k3s server with the default SQLite datastore. RSSHub can run
on T2 or T3, preferring T3, and uses its own bounded in-memory cache. T2 is an
agent alongside its desktop and API-backed tools. Both nodes are installed and
have been verified Ready. Node names are `t3` and `t2`, labelled
`homelab-role=services` and `homelab-role=work`. T1 and MON1 remain outside
Kubernetes.

This is **not HA**: T2 is not a second control-plane server and cannot replace
T3's datastore. RSSHub no longer depends on a Redis service on T3, but losing
T3 still loses the control plane. Cache contents are disposable and reset with
each RSSHub pod; durable services need separately designed persistent storage.

## Bootstrap and configuration

1. The parent provisioning flow must create
   `secrets/homelab/k3s-token.age` in `infra-nixCfg-secrets`, encrypted for the
   bootstrap identity, and update the private input before CI evaluation.
   Use the same strong, randomly generated join token on both hosts. Do not
   put its plaintext in a Nix expression, command argument, or manifest.
2. Seed `/var/lib/agenix/id_ed25519` (root-only, mode 0600) on both hosts
   before activation. The shared module imports agenix and decrypts the token
   to `/run/agenix/k3s-token` with mode 0400. k3s reads that file at runtime;
   only encrypted data enters the Nix store.
3. Verify `T3.lan` resolves to T3's LAN address from T2 and MON1. The router's
   DHCP/DNS configuration is authoritative; no fixed address is assumed here.
   Ensure DHCP-provided LAN DNS remains usable alongside common public DNS
   settings. Bring up T3 first, then T2. The worker joins
   `https://T3.lan:6443`; the server certificate includes `T3.lan` as a TLS SAN.
4. Keep the API, kubelet, VXLAN and NodePort on trusted LAN/tailnet networks.
   Do not forward these from the WAN. The common host layer currently disables
   the host firewall; the k3s modules still declare TCP 10250 and 31200 and UDP 8472 on
   both nodes, plus TCP 6443 on T3 for when it is enabled. CNI and
   flannel interfaces are trusted; NetworkManager leaves CNI, flannel and veth
   interfaces unmanaged. The router's network isolation remains essential.

The default flannel VXLAN networking, CoreDNS, local-path storage provisioner
and metrics server remain enabled. Traefik and ServiceLB are disabled: RSSHub
uses NodePort, so no Ingress, ingress DNS, certificates or host ports 80/443 are
required. Default pod/service CIDRs must not overlap an existing network.

Both nodes reserve 250 millicores and 512 MiB for Kubernetes. T2 additionally
reserves 1 CPU and 2 GiB for host work; T3 reserves 500 millicores and 1 GiB.
Kubelet evicts under memory/disk pressure. Reservations reduce pod allocatable
capacity; they neither cap host processes nor guarantee desktop responsiveness
under arbitrary load. Size additional pod requests/limits before scheduling
work onto T2. Role labels are scheduling hints, not isolation or taints.

## RSSHub and its cache

`hosts/nixos/T3/rsshub.nix` declares a single RSSHub deployment and NodePort
service at `http://T3.lan:31200` (also reachable through T2). The image is pinned
to upstream commit `b4990a809138010275532fbab0efe8d55e2dc779`.

RSSHub uses `CACHE_TYPE=memory`, `MEMORY_MAX=256`, a 300-second route TTL and
3600-second content TTL. These are supported by the
[pinned upstream configuration](https://github.com/DIYgod/RSSHub/blob/b4990a809138010275532fbab0efe8d55e2dc779/lib/config.ts).
Redis was previously only a cache for RSSHub; no user datastore depended on it.
The deployment no longer declares a Redis service or pod. Its retired PVC stays
declared solely to prevent k3s from pruning its existing data.
Cache entries reset when RSSHub restarts and are not shared between replicas.
Keep one replica unless independent per-pod caches are acceptable.

Migration: apply the new RSSHub manifest, wait for the rollout, and verify a
real RSS feed. The k3s AddOn controller can prune Deployment and Service objects
removed from the manifest. Preserve the old `rsshub/redis-data` PVC declaration
and its PV: pruning that claim may erase data.
They can be inspected and retired separately after the owner approves cleanup.
Do not delete the namespace, which also owns the running RSSHub resources.

The small RSSHub image omits Chromium. Browser-dependent routes require a
separately planned browser service or image change. Supply route credentials
through runtime Kubernetes Secrets, never plaintext manifests.

## SSH portfolio

`hosts/nixos/T3/ssh-portfolio.nix` runs the
[Qezta/ssh](https://github.com/Qezta/ssh) terminal portfolio
(`ssh divit@qezta.com`) in the `qezta-ssh` namespace. The `qezta-ssh` flake
input builds a static OCI image, and `services.k3s.images` preloads it into
T3's containerd, so no registry or image pull is involved
(`imagePullPolicy: Never`). The image tag is its content hash: bumping the
input changes the Deployment, and the image change restarts `k3s.service` so
the new tarball is imported. Pods keep running across that restart.

The pod requires node `t3`. Its 16 MiB local-path PVC holds the server host
key, which the server generates on first start. Clients pin that key, so
treat the PVC like a secret: back it up, and never delete it casually.
The pod runs as UID 65532 with a read-only root filesystem, no capabilities and
no service-account token; it is limited to 128 MiB/500 millicores. Sessions
time out after 15 minutes idle or 2 hours total.

The Service is NodePort **30022** with `externalTrafficPolicy: Local`, which
keeps real client addresses in the connection log. LAN test:
`ssh -p 30022 divit@T3.lan`. Unlike the other NodePorts, this one is meant to be
public: the remaining step is a router forward from WAN TCP 22 to
`T3.lan:30022`, plus a DNS A record for `qezta.com` (or `ssh.qezta.com`) that
points at the WAN address and is not proxied. The server never grants a shell
and accepts any credentials by design (see Qezta/ssh `SECURITY.md`).

```sh
sudo k3s kubectl -n qezta-ssh get deployment,pods,service,pvc
sudo k3s kubectl -n qezta-ssh logs deployment/ssh-portfolio
```

## Operations after installation

On T3, use root's local kubeconfig (`sudo k3s kubectl ...`):

```sh
sudo k3s kubectl get nodes -L homelab-role
sudo k3s kubectl -n rsshub get deployments,pods,services,pvc
sudo k3s kubectl -n rsshub rollout status deployment/rsshub
sudo k3s kubectl -n rsshub logs deployment/rsshub
sudo k3s kubectl -n rsshub get events --sort-by=.lastTimestamp
curl --fail http://T3.lan:31200/
sudo journalctl -u k3s
```

Verify both nodes are Ready, RSSHub is Available, a real feed responds and
MON1's RSSHub probe succeeds. Check T2's allocatable resources and desktop
responsiveness before adding workloads. Kubeconfigs contain credentials: keep
them root-only and never commit them.

Back up T3's `/var/lib/rancher/k3s/server/db` SQLite state with k3s stopped,
along with the server token in `/var/lib/rancher/k3s/server/token`, protecting
the token as a secret. RSSHub cache does not need backing up. Keep the bootstrap age identity recoverable.
Test restoration onto T3 before treating backups as usable. A second agent
cannot recover the server database.

NixOS rebuilds update the auto-deploy manifest. The pinned k3s AddOn controller
[prunes previously owned objects removed from a changed manifest](https://github.com/k3s-io/k3s/blob/v1.35.6%2Bk3s1/pkg/deploy/controller.go#L229).
Removing the manifest file is a different operation and must not be relied on
for cleanup. Deleting or pruning a PVC may reclaim its local data. Do not delete the namespace/PVC casually. T3 rebuilds, Recreate
rollouts and reboots can interrupt service. Upgrade server first, then agent,
and keep their k3s versions compatible.

## Validation and sources

Follow `.apm/instructions/ci-eval.instructions.md`: complete host evaluation
belongs in `.github/workflows/eval.yml` on native GitHub runners. The parent
integrator must evaluate T2, T3 and MON1 after staging these new modules and
updating the private secret input. Local validation is limited to formatting,
Nix parsing, standalone manifest evaluation and Kubernetes schema checks.
The previous fleet rollout verified both nodes Ready, cross-node service access,
a real RSS feed and healthy system pods. Validate the Redis removal against a
new feed request and the resulting deployment environment; historical Redis
persistence checks do not prove this migration succeeded.

- [Pinned nixpkgs k3s module](https://github.com/NixOS/nixpkgs/blob/6201e203d09599479a3b3450ed24fa81537ebc4e/nixos/modules/services/cluster/rancher/k3s.nix)
  and [shared Rancher options](https://github.com/NixOS/nixpkgs/blob/6201e203d09599479a3b3450ed24fa81537ebc4e/nixos/modules/services/cluster/rancher/default.nix)
  define `manifests.*.content`, `extraKubeletConfig`, `nodeName`, `nodeLabel`,
  `tokenFile`, and the default standalone SQLite behavior.
- [k3s requirements and ports](https://docs.k3s.io/installation/requirements),
  [packaged components and manifest lifecycle](https://docs.k3s.io/installation/packaged-components),
  [SQLite backup/restore](https://docs.k3s.io/datastore/backup-restore)
  and [local-path storage](https://docs.k3s.io/storage).
- [RSSHub upstream release and published image tags](https://github.com/DIYgod/RSSHub/releases/tag/v2026.11.16-8658.b4990a8).
