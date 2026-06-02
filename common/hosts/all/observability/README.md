# Observability Subsystem

A declarative Prometheus + Loki + Tempo + Grafana + Alertmanager + OTEL Collector stack for the OS-nixCfg fleet, with Nix-specific metrics ("rebuild durations", "flake-lock age", "store size growth") that turn a generic LGTM deployment into a real Nix-platform-engineering story.

## Architecture

```
                   ┌──────────────────────────┐
                   │      obs-host (L2)       │
                   │                          │
                   │  prometheus  ◄── scrape  │
                   │  loki        ◄── push    │
                   │  tempo       ◄── OTLP    │
                   │  alertmanager            │
                   │  grafana                 │
                   │  otelcol     ◄── OTLP    │
                   │  blackbox    ── probe ─►─┐
                   └──────────────────────────┘ │
                          ▲    ▲    ▲           │
                          │    │    │           │
                       ┌──┴─┐ ┌┴──┐ ┌┴──┐       │
                       │ T2 │ │WSL│ │ L1│ ◄── ping
                       └────┘ └───┘ └───┘   ▲
                       node_exporter        │
                       alloy (logs+otlp)    │
                       nix-exporter         │
                       smartctl_exporter ───┘
```

L2 runs the server stack. T2/WSL/L1 (Darwin) run the agent stack.

## Enabling

In a host config (already done for L2/T2/WSL/L1):

```nix
services.observability = {
  enable = true;
  role = "server";   # or "agent"
  serverHost = "L2";
  fleet.hosts = [
    { name = "L2"; address = "l2.example.ts.net"; class = "nixos"; }
    { name = "T2"; address = "t2.example.ts.net"; class = "nixos"; }
    # …
  ];
};
```

Replace `address` values with your real Tailscale / WireGuard hostnames.

## Secrets

Two optional secrets, both managed via agenix:

| Secret                           | Purpose                             |
| -------------------------------- | ----------------------------------- |
| `observability/alertmanager.env` | `NTFY_TOPIC_URL`, `DISCORD_WEBHOOK` |
| `observability/grafana-admin`    | Initial Grafana admin password      |

Wire them in `hosts/nixos/L2/observability.nix`.

## Dashboards

Provisioned from `common/hosts/nixos/observability/dashboards/`:

- **Fleet Overview** — host status grid, CPU/mem aggregates, per-host table with rebuild + lock age.
- **Per-Host Drilldown** — host-templated CPU/mem/disk/network, failed units, recent journal logs.
- **Nix Health** — store size, rebuild duration heatmap + P95, generations, GC roots, flake-lock age. **This is the screenshot for the README.**
- **Network Mesh** — pairwise ping RTT, cert expiry table, DNS success rate.

Edit the JSON directly, or grab the latest from the running Grafana via "Share → Export" and overwrite.

## What's collected

### Metrics (Prometheus)

- `node_exporter` standard collectors + `textfile` + `systemd`.
- `nix-exporter` (custom): store size, paths, GC roots, last-GC ts, last-rebuild ts, flake-lock age, generations per profile.
- `nixos-rebuild` duration (manual histogram emission via the wrapper script).
- `smartctl_exporter` drive health.
- `blackbox_exporter` for ICMP / TCP / HTTPS / DNS probes.
- Self-metrics for every service.

### Logs (Loki)

- NixOS: `systemd-journald` → Grafana Alloy → Loki.
- Darwin: macOS unified log → Vector → Loki.
- (Optional) GitHub Actions CI logs via `flake/actions/log-shipping.nix`.

### Traces (Tempo)

- Tempo + OTEL Collector with tail-sampling are wired and ready.
- No application is instrumented yet — see notes below.

## Adding traces

Instrument an app with OTLP. Point it at the local Alloy agent (`127.0.0.1:4317`) — Alloy forwards to the obs-host's OTEL Collector, which tail-samples (keep errors + slow > 500ms + 5% baseline) before persisting to Tempo.

```python
# DocAssist-LLM example
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint="127.0.0.1:4317", insecure=True))
)
trace.set_tracer_provider(provider)
```

## CI log shipping

`flake/actions/log-shipping.nix` defines a `workflow_run`-triggered workflow that fetches the just-completed run's log via `gh run view --log` and POSTs it to Loki.

Configure repo secrets:

- `LOKI_PUSH_URL` (required) — e.g. `https://loki.example.ts.net/loki/api/v1/push`
- `LOKI_BASIC_AUTH` (optional) — `user:password` (will be base64-encoded)

Without these the step is a no-op.

## Local preview (services-flake)

For iterating on dashboards, alert rules, or scrape configs without rebuilding L2, the full stack can be booted on the developer's laptop via [services-flake](https://github.com/juspay/services-flake):

```bash
observe                  # devshell shortcut (preferred)
# or:
nix run .#observability
```

This brings up the same LGTM-A pipeline as the obs-host — Prometheus, Loki, Tempo, Grafana, Alertmanager, OTEL Collector, blackbox_exporter, and node_exporter — wired together with the **same generators** under [`lib/observability/`](../../../../lib/observability), so a config that works locally also works on L2.

Once healthy, open **http://127.0.0.1:3000** (`admin` / `admin`). Datasources and dashboards are provisioned from [`common/hosts/nixos/observability/dashboards/`](../../nixos/observability/dashboards/). Panels referencing fleet-only metrics (e.g. `nix_store_size_bytes`) will show "No data" — only `node_exporter` self-metrics will be live.

State lives under `$HOME/.local/share/process-compose/` (the per-service `dataDir` is managed by services-flake) and is wiped between runs unless you launch with `--keep-tui`. Retention is shortened (24h metrics, 12h logs, 1h traces) so a long-running preview doesn't blow up the disk. Alertmanager's webhook URLs fall back to `/dev/null` — no notifications fire unless you set `NTFY_TOPIC_URL` / `DISCORD_WEBHOOK` in the environment before launching.

Implementation: [`flake/services.nix`](../../../../flake/services.nix).

## Ports (defaults)

| Service             | Port  |
| ------------------- | ----- |
| Prometheus          | 9090  |
| Grafana             | 3000  |
| Loki                | 3100  |
| Tempo (HTTP)        | 3200  |
| Tempo OTLP gRPC     | 4317  |
| Tempo OTLP HTTP     | 4318  |
| Alertmanager        | 9093  |
| node_exporter       | 9100  |
| smartctl_exporter   | 9633  |
| blackbox_exporter   | 9115  |
| Alloy (server)      | 12345 |
| OTEL Collector gRPC | 4319  |
| OTEL Collector HTTP | 4320  |

Override via `services.observability.ports.*`.

## Operating notes

- Data lives under `/var/lib/observability/` — back this up if you care about historical metrics/logs.
- Retention defaults: 90d metrics, 30d logs, 72h traces.
- Loki labels are kept low-cardinality (host, unit, level, class). Anything per-request belongs in the log body, queryable via `|=` / `| json`.
- The textfile collector dir is `/var/lib/observability/node-textfile` on NixOS, `/Library/Application Support/observability/textfile` on macOS.
