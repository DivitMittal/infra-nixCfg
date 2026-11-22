# Homelab k3s

T3 runs the sole k3s server with the default SQLite datastore and hosts Redis.
Stateless RSSHub can run on T2 or T3, preferring T3. T2 joins as an agent alongside
its GUI and API-backed AI agents. Kubernetes node names are `t3` and `t2`, with
`homelab-role=services` and `homelab-role=work` labels respectively. T1 remains
the router outside Kubernetes; MON1 remains an external monitoring host.

This is **not HA**. Losing T3 loses the control plane and Redis even
while T2 is healthy. An RSSHub pod on T2 still depends on Redis on T3; this
placement flexibility does not provide service failover. T2 is not a second server and provides no datastore
redundancy. T3 was installed and verified on 2026-11-18: its node is Ready,
RSSHub and Redis are healthy, and Redis's local volume survives pod replacement.
T2 still awaits installation and has not joined the cluster.

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

## RSSHub and Redis

`hosts/nixos/T3/rsshub.nix` supplies a single k3s auto-deploy manifest containing
the `rsshub` namespace, two single-replica Deployments, two Services and a
2 GiB Redis PVC. The native RSSHub module is disabled and no native Redis
instance is configured. Redis requires node `t3` and the services label.
RSSHub has soft preferred node affinity for `homelab-role=services`, with no
required node selector: the scheduler can place it on either T640 compute node
according to available resources. Existing pods are not automatically moved
back to T3 when capacity changes.
Redis uses the default `local-path` storage class, ReadWriteOnce and Recreate
rollouts, with AOF persistence under `/data`. Its cache uses a 192 MiB
allkeys-LRU bound; its container is limited to 384 MiB/500 millicores. RSSHub
requests 256 MiB/100 millicores and is limited to 768 MiB/1 CPU. Both have
readiness/liveness probes; RSSHub also has a startup probe.

The endpoint is **http://T3.lan:31200**, replacing native port 1200. MON1's
blackbox target and the topology annotation use this URL. NodePort uses
`externalTrafficPolicy: Cluster`, so T3 forwards to RSSHub even when its pod
runs on T2. Both nodes expose NodePort 31200; T3 remains the advertised endpoint.
Redis remains cluster-internal. The small RSSHub image omits Chromium, so routes
requiring a browser need a separately planned browser service or image change.
Per-route credentials must be provided through runtime Kubernetes Secrets and
`secretKeyRef`/`envFrom`, never plaintext manifest values.

The RSSHub image is pinned to upstream commit
`b4990a809138010275532fbab0efe8d55e2dc779`; Redis uses the explicit version
`7.4.12-alpine3.22`. These are versioned tags, not digest locks: future updates
should verify upstream provenance, test the release, and preferably pin an
OCI manifest digest. No mutable `latest` tag is used.

A local-path PVC is tied to T3's disk; it does not replicate to T2. Losing the
node/disk loses the Redis cache unless backed up. The requested 2 GiB is not a
filesystem quota for local-path, so monitor free space and AOF growth. Cache
can be recreated if losing cached feeds is acceptable. There is no existing
native cache migration because these hosts are uninstalled.

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

## Onion and IPFS endpoints

Clearnet is unchanged: Vercel still serves qezta.com and divit.qezta.com
(DNS in Qezta/infra). SSH still needs the WAN forward above for
`ssh divit@qezta.com`.

Kubernetes is only the SSH server. `hosts/nixos/T3/ssh-portfolio.nix` is the
Deployment and the NodePort Service, and the `qezta-ssh` hidden service in
that same file forwards virtual port 22 to that NodePort. There is no second
pod. The Service annotation `qezta.com/onion-service` records the link.
Website onions are not pods. nginx on localhost serves the site build or
proxies the declared upstream. Tor and Kubo keep host keys and the IPFS
repo on disk.

`hosts/nixos/T3/qezta-endpoints.nix` generates the website onions, the nginx
listeners, and the IPFS pins from `proxies` and `ipfsRoots`. It does not
scrape Vercel. `qezta-www` serves the Nix build of
[Qezta/site](https://github.com/Qezta/site) (`adapter-static`, relative
`_app` paths, Vercel analytics removed). That same store path is the `qezta`
IPNS pin. The static portfolio is published under the `divit` IPNS key.
It omits chat. The `divit-www` onion proxies to Vercel to keep chat available.
The separate `endpoints` pin contains only the declarative endpoint record.
Publish DNSLink TXT records at `_dnslink.qezta.com` and
`_dnslink.divit.qezta.com` once the matching IPNS names are published and
verified. The names are recorded in `/var/lib/qezta-endpoints/endpoints.txt`.

Tor needs no inbound port. Hostnames are state, copied to
`/var/lib/qezta-endpoints/endpoints.txt`.

| Name               | What it is                                                              |
| ------------------ | ----------------------------------------------------------------------- |
| `onion.qezta-www`  | static Qezta/site build (same path as `ipns.qezta`)                     |
| `onion.divit-www`  | HTTP reverse proxy to `https://divit.qezta.com` (chatbot included)      |
| `onion.qezta-ssh`  | virtual port 22 to the portfolio NodePort. `torsocks ssh divit@<onion>` |
| `onion.qezta-ipfs` | path gateway for local pins only (`/ipfs/`, `/ipns/`)                   |
| `ipns.qezta`       | static company site build                                               |
| `ipns.divit`       | static portfolio build with chat disabled                               |
| `ipns.endpoints`   | `endpoints.json` and a short index. Not the site                        |

The divit proxy rewrites `Host` to the Vercel name, drops HSTS and CSP (so
the browser does not upgrade the onion to HTTPS), and does not forward the
client address. Chat requests on that onion transit T3 on their way to Vercel.
The site pin still loads Three.js from cdnjs for the cursor. `@qezta/ui`'s
font URLs do not resolve in the build (the same unresolved urls the Vercel
build emits). Those are not `/_app` assets. Onion hostnames and IPNS ids do
not exist until T3 activates this config.

Kubo is a DHT client capped at 2 GiB of repo and 768 MiB of RAM. Its gateway
is `127.0.0.1:8082` with `Gateway.NoFetch`, so it is not an open proxy and
does not take Attic's port 8080. It does not relay other people's traffic.
Swarm is TCP/UDP 4001. A WAN forward of 4001 is optional and not declared;
relay clients cover the NAT. IPNS lifetime is 7 days; the publisher runs when
the pinned store path changes, and again at boot.

Once onion hostnames exist, the site repos can advertise them with an
`Onion-Location` header. That header is not set from this flake.

```sh
cat /var/lib/qezta-endpoints/endpoints.txt
sudo k3s kubectl -n qezta-ssh get svc ssh-portfolio -o jsonpath='{.metadata.annotations}'
systemctl status qezta-ipfs-publish.service qezta-endpoints.service
```

## Operations after installation

On T3, use root's local kubeconfig (`sudo k3s kubectl ...`):

```sh
sudo k3s kubectl get nodes -L homelab-role
sudo k3s kubectl -n rsshub get deployments,pods,services,pvc
sudo k3s kubectl -n rsshub rollout status deployment/redis
sudo k3s kubectl -n rsshub rollout status deployment/rsshub
sudo k3s kubectl -n rsshub logs deployment/rsshub
sudo k3s kubectl -n rsshub get events --sort-by=.lastTimestamp
curl --fail http://T3.lan:31200/
sudo journalctl -u k3s
```

Verify both nodes are Ready, Redis's PVC is Bound on T3, both deployments are
Available, and MON1's RSSHub probe succeeds. Restart the Redis pod and check
cache persistence. Check T2's allocatable resources and GUI responsiveness
before adding agent workloads. Kubeconfigs contain credentials: keep them
root-only and never commit them.

Back up T3's `/var/lib/rancher/k3s/server/db` SQLite state with k3s stopped,
along with the server token in `/var/lib/rancher/k3s/server/token`, protecting
the token as a secret. Back up the Redis volume separately with Redis stopped
if cache restoration matters. Keep the bootstrap age identity recoverable.
Test restoration onto T3 before treating backups as usable. A second agent
cannot recover the server database.

NixOS rebuilds update the auto-deploy manifest. Removing entries or the file
does **not** garbage-collect Kubernetes resources. Plan explicit `kubectl`
cleanup after removing declarative ownership; deleting a PVC may reclaim its
local data. Do not delete the namespace/PVC casually. T3 rebuilds, Recreate
rollouts and reboots can interrupt service. Upgrade server first, then agent,
and keep their k3s versions compatible.

## Validation and sources

Follow `.apm/instructions/ci-eval.instructions.md`: complete host evaluation
belongs in `.github/workflows/eval.yml` on native GitHub runners. The parent
integrator must evaluate T2, T3 and MON1 after staging these new modules and
updating the private secret input. Local validation is limited to formatting,
Nix parsing, standalone manifest evaluation and Kubernetes schema checks.
The focused whole-host CI evaluation passed for T1/T2/T3/MON1. T3 was then
installed and booted from NVMe. Live checks confirmed a real RSS feed, healthy
system pods, a Bound Redis PVC, and a temporary Redis test value surviving pod
replacement. T2 scheduling remains untested until the worker joins.

- [Pinned nixpkgs k3s module](https://github.com/NixOS/nixpkgs/blob/6201e203d09599479a3b3450ed24fa81537ebc4e/nixos/modules/services/cluster/rancher/k3s.nix)
  and [shared Rancher options](https://github.com/NixOS/nixpkgs/blob/6201e203d09599479a3b3450ed24fa81537ebc4e/nixos/modules/services/cluster/rancher/default.nix)
  define `manifests.*.content`, `extraKubeletConfig`, `nodeName`, `nodeLabel`,
  `tokenFile`, and the default standalone SQLite behavior.
- [k3s requirements and ports](https://docs.k3s.io/installation/requirements),
  [packaged components and manifest lifecycle](https://docs.k3s.io/installation/packaged-components),
  [SQLite backup/restore](https://docs.k3s.io/datastore/backup-restore)
  and [local-path storage](https://docs.k3s.io/storage).
- [RSSHub upstream release and published image tags](https://github.com/DIYgod/RSSHub/releases/tag/v2026.11.16-8658.b4990a8)
  and [official Redis image tags](https://hub.docker.com/_/redis/tags?name=7).
