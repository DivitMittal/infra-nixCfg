## Ships CI logs from this repo's workflows into Loki.
##
## How it works:
##   - Each existing workflow (flake-check, *-build, …) emits its own logs into
##     GitHub's job log buffer. We add a `post:` step that, on workflow completion,
##     fetches the job log via `gh run view --log` and POSTs it to Loki.
##
## Secrets used:
##   - LOKI_PUSH_URL   : e.g. https://loki.example.ts.net/loki/api/v1/push
##   - LOKI_BASIC_AUTH : "user:password" base64-encoded (optional)
##
## To enable on a workflow, append `log-shipping-step` to its job's `steps`.
{
  common-permissions,
  environment,
  ...
}: {
  _module.args.log-shipping-step = {
    name = "Ship CI logs to Loki";
    "if" = "always() && env.LOKI_PUSH_URL != ''";
    env = {
      LOKI_PUSH_URL = "\${{ secrets.LOKI_PUSH_URL }}";
      LOKI_BASIC_AUTH = "\${{ secrets.LOKI_BASIC_AUTH }}";
      GH_TOKEN = "\${{ github.token }}";
    };
    run = ''
      set -euo pipefail
      if [[ -z "''${LOKI_PUSH_URL:-}" ]]; then
        echo "LOKI_PUSH_URL not set — skipping log shipping."
        exit 0
      fi

      # Pull the full log for the current run; gh CLI is pre-installed on the runner.
      LOG_FILE=$(mktemp)
      gh run view "''${GITHUB_RUN_ID}" --log >"$LOG_FILE" || {
        echo "Could not fetch run log; skipping."
        exit 0
      }

      # Build a Loki streams payload — each line becomes one entry.
      python3 - <<'PY' "$LOG_FILE" "''${GITHUB_REPOSITORY}" "''${GITHUB_WORKFLOW}" "''${GITHUB_RUN_ID}" "''${GITHUB_SHA}"
      import json, sys, time, urllib.request, os, base64
      log_path, repo, workflow, run_id, sha = sys.argv[1:6]
      now_ns = str(time.time_ns())
      values = []
      with open(log_path) as f:
          for line in f:
              line = line.rstrip("\n")
              if not line:
                  continue
              values.append([now_ns, line])
      payload = json.dumps({
          "streams": [{
              "stream": {
                  "job": "github-actions",
                  "repo": repo,
                  "workflow": workflow,
                  "run_id": run_id,
                  "sha": sha,
              },
              "values": values,
          }]
      }).encode()
      req = urllib.request.Request(
          os.environ["LOKI_PUSH_URL"],
          data=payload,
          headers={"Content-Type": "application/json"},
          method="POST",
      )
      auth = os.environ.get("LOKI_BASIC_AUTH", "").strip()
      if auth:
          req.add_header("Authorization", "Basic " + base64.b64encode(auth.encode()).decode())
      with urllib.request.urlopen(req, timeout=30) as resp:
          print("Loki push:", resp.status)
      PY
    '';
  };

  ## Standalone "ship arbitrary logs" workflow — triggered manually or by
  ## workflow_run from any completed workflow, ships its logs without needing
  ## per-workflow modification. This is the lower-friction option.
  flake.actions-nix.workflows.".github/workflows/log-shipping.yml" = {
    on = {
      workflow_run = {
        workflows = ["flake-check" "nixos-build" "darwin-build" "home-build" "topology-build" "iso-release"];
        types = ["completed"];
      };
      workflow_dispatch = {};
    };
    jobs.ship = {
      permissions =
        common-permissions
        // {
          actions = "read";
        };
      inherit environment;
      steps = [
        {
          name = "Checkout (cheap)";
          uses = "actions/checkout@main";
          "with" = {
            fetch-depth = 1;
            persist-credentials = false;
          };
        }
        {
          name = "Ship logs to Loki";
          env = {
            LOKI_PUSH_URL = "\${{ secrets.LOKI_PUSH_URL }}";
            LOKI_BASIC_AUTH = "\${{ secrets.LOKI_BASIC_AUTH }}";
            GH_TOKEN = "\${{ github.token }}";
            TRIGGER_RUN_ID = "\${{ github.event.workflow_run.id }}";
            TRIGGER_WORKFLOW = "\${{ github.event.workflow_run.name }}";
          };
          run = ''
            set -euo pipefail
            [[ -n "''${LOKI_PUSH_URL:-}" ]] || { echo "no LOKI_PUSH_URL; skip"; exit 0; }
            LOG_FILE=$(mktemp)
            gh run view "$TRIGGER_RUN_ID" --log >"$LOG_FILE" || exit 0

            python3 - <<'PY' "$LOG_FILE" "''${GITHUB_REPOSITORY}" "$TRIGGER_WORKFLOW" "$TRIGGER_RUN_ID"
            import json, sys, time, urllib.request, os, base64
            log_path, repo, workflow, run_id = sys.argv[1:5]
            now_ns = str(time.time_ns())
            values = [[now_ns, ln.rstrip("\n")] for ln in open(log_path) if ln.strip()]
            payload = json.dumps({"streams":[{"stream":{
                "job":"github-actions","repo":repo,"workflow":workflow,"run_id":run_id
            },"values":values}]}).encode()
            req = urllib.request.Request(os.environ["LOKI_PUSH_URL"], data=payload,
                headers={"Content-Type":"application/json"}, method="POST")
            auth = os.environ.get("LOKI_BASIC_AUTH","").strip()
            if auth:
                req.add_header("Authorization", "Basic " + base64.b64encode(auth.encode()).decode())
            with urllib.request.urlopen(req, timeout=30) as r:
                print("Loki push:", r.status)
            PY
          '';
        }
      ];
    };
  };
}
