# Build-only offload to a private signed cache, with encrypted artifact fallback.
{
  attic,
  common-actions,
  environment,
  ...
}: let
  atticTarget = "${attic.remote}:${attic.darwinCache}";
  privateCacheEnv = {
    ATTIC_DARWIN_TOKEN = "\${{ secrets.ATTIC_DARWIN_TOKEN }}";
    DARWIN_CACHE_PUBLIC_KEY = "\${{ vars.DARWIN_CACHE_PUBLIC_KEY }}";
    ATTIC_ENDPOINT = attic.endpoint;
    ATTIC_REMOTE = attic.remote;
    ATTIC_DARWIN_CACHE = attic.darwinCache;
  };
in {
  flake.actions-nix.workflows.".github/workflows/darwin-offload.yml" = {
    on.push = {
      branches = ["master"];
      paths = [
        "flake.nix"
        "flake.lock"
        "flake/**"
        "common/**"
        "home/**"
        "hosts/darwin/**"
        "modules/**"
        "overlays/**"
        "pkgs/**"
      ];
    };
    on.workflow_dispatch.inputs.target = {
      description = "Native Darwin target (build only)";
      type = "choice";
      options = ["L1" "ASL1"];
      default = "L1";
      required = true;
    };
    jobs.build = {
      concurrency = {
        group = "darwin-cache-network-probe";
        cancel-in-progress = true;
      };
      runs-on = "\${{ inputs.target == 'ASL1' && 'macos-15' || 'macos-15-intel' }}";
      timeout-minutes = 15;
      permissions.contents = "read";
      inherit environment;
      steps = let
        originalSteps =
          [
            {
              name = "Require encrypted transport";
              env.ARTIFACT_RECIPIENT = "\${{ vars.CACHE_ARTIFACT_RECIPIENT }}";
              run = ''
                test -n "$ARTIFACT_RECIPIENT" || { echo "Set dev variable CACHE_ARTIFACT_RECIPIENT to the importer's public age recipient" >&2; exit 1; }
              '';
            }
          ]
          # Shared infra allows anonymous reads. Only the separate authenticated
          # darwin cache may receive these closures; no shared Actions uploads.
          ++ builtins.filter (step:
            !(builtins.elem (step.name or "") [
              "Magic Nix Cache(Use Github Actions Cache)"
              "Check for attic credentials"
              "Join the tailnet to reach attic on T3"
              "Use the attic cache on T3"
            ]))
          common-actions
          ++ [
            {
              name = "Check private Darwin cache credentials";
              id = "darwin_credentials";
              run = "echo \"enabled=\${{ secrets.ATTIC_DARWIN_TOKEN != '' && secrets.TS_OAUTH_CLIENT_ID != '' && secrets.TS_OAUTH_SECRET != '' && vars.DARWIN_CACHE_PUBLIC_KEY != '' }}\" >> \"$GITHUB_OUTPUT\"";
            }
            {
              name = "Join the tailnet for the private Darwin cache";
              id = "darwin_tailnet";
              timeout-minutes = 10;
              "if" = "steps.darwin_credentials.outputs.enabled == 'true'";
              env.TS_OAUTH_SECRET = "\${{ secrets.TS_OAUTH_SECRET }}";
              run = ''
                rev=$(jq -r '.nodes["nixpkgs-2605"].locked.rev' flake.lock)
                nix profile install "github:NixOS/nixpkgs/$rev#tailscale" "github:NixOS/nixpkgs/$rev#attic-client"
                python3 flake/actions/darwin-tailnet.py
              '';
              continue-on-error = true;
            }
            {
              name = "Use only the private pinned Darwin cache";
              id = "darwin_cache";
              "if" = "steps.darwin_tailnet.outcome == 'success'";
              env = privateCacheEnv;
              run = ''
                python3 flake/actions/darwin-network-probe.py --prepare
                  python3 flake/actions/darwin-cache.py
                attic use ${atticTarget}
              '';
              continue-on-error = true;
            }
            {
              name = "Prove signed private cache push and independent pull";
              id = "darwin_probe";
              "if" = "steps.darwin_cache.outcome == 'success'";
              env = privateCacheEnv;
              shell = "bash";
              run = ''
                set -euo pipefail
                printf '%s\n' "darwin-cache-probe $GITHUB_RUN_ID $GITHUB_RUN_ATTEMPT" > "$RUNNER_TEMP/darwin-probe.txt"
                probe=$(nix-store --add "$RUNNER_TEMP/darwin-probe.txt")
                attic push --no-closure -j 2 ${atticTarget} "$probe"
                python3 flake/actions/darwin-cache.py "$probe"
                nix copy --from ${attic.darwinStore} \
                  --to "local?root=$RUNNER_TEMP/darwin-probe-store" \
                  --option require-sigs true --option trusted-public-keys "$DARWIN_CACHE_PUBLIC_KEY" "$probe"
                cmp "$probe" "$RUNNER_TEMP/darwin-probe-store$probe"
                echo "Private Darwin cache: authenticated push, anonymous narinfo denied, signed independent pull passed" >> "$GITHUB_STEP_SUMMARY"
              '';
              continue-on-error = true;
            }
            {
              name = "Build on native Darwin";
              id = "darwin_build";
              # Leave time inside the job limit to cache partial progress.
              timeout-minutes = 285;
              env.TARGET = "\${{ inputs.target || 'L1' }}";
              shell = "bash";
              run = ''
                set -euo pipefail
                # Snapshot valid paths so a later step can push whatever this run
                # built, even if it fails or times out. `attic watch-store` is not
                # usable here: its kqueue watcher hits EMFILE on /nix/store.
                nix path-info --all | sort > "$RUNNER_TEMP/store-before.txt"
                case "$TARGET" in
                  L1) test "$(uname -m)" = x86_64 ;;
                  ASL1) test "$(uname -m)" = arm64 ;;
                  *) echo "Unsupported target" >&2; exit 1 ;;
                esac
                # macOS's Bash 3.2 treats an empty array as unset under nounset.
                set --
                if [ -n "$LOCAL_OVERRIDES" ]; then
                  read -r -a local_overrides <<< "$LOCAL_OVERRIDES"
                  set -- "''${local_overrides[@]}"
                fi
                # Upstream fetches (e.g. GitHub commit .patch URLs) intermittently
                # return 503. --keep-going lets unrelated paths finish (and reach
                # the incremental uploader); retries only redo what is missing.
                build() {
                  local attempt
                  for attempt in 1 2 3; do
                    if nix build --accept-flake-config --no-write-lock-file --keep-going \
                      --max-jobs 2 --cores 2 --option fallback true "$@"; then
                      return 0
                    fi
                    if [ "$attempt" -lt 3 ]; then
                      echo "::warning::nix build attempt $attempt failed; retrying in $((attempt * 60))s"
                      sleep $((attempt * 60))
                    fi
                  done
                  return 1
                }
                # Attempt both closures so one failure doesn't block caching the other.
                status=0
                build ".#darwinConfigurations.$TARGET.system" --out-link result-system "$@" || status=1
                build ".#homeConfigurations.$TARGET.activationPackage" --out-link result-home "$@" || status=1
                [ "$status" -eq 0 ]
                readlink -f result-system > deployment-paths.txt
                readlink -f result-home >> deployment-paths.txt
                printf '%s\n' "$GITHUB_SHA" > source-revision.txt
              '';
            }
            {
              name = "Push newly built paths to the private Darwin cache";
              "if" = "always() && steps.darwin_probe.outcome == 'success'";
              timeout-minutes = 55;
              env = privateCacheEnv;
              shell = "bash";
              run = ''
                set -euo pipefail
                before="$RUNNER_TEMP/store-before.txt"
                test -f "$before" || { echo "No pre-build snapshot; nothing to push"; exit 0; }
                nix path-info --all | sort | comm -13 "$before" - | grep -v '\.drv$' > "$RUNNER_TEMP/store-new.txt" || true
                count=$(wc -l < "$RUNNER_TEMP/store-new.txt" | tr -d ' ')
                echo "New store paths after build: $count" >> "$GITHUB_STEP_SUMMARY"
                [ "$count" -gt 0 ] || exit 0
                python3 flake/actions/darwin-cache.py
                # Uploads have run at KiB/s; record whether the path to T3 is
                # direct or DERP-relayed so throughput can be diagnosed.
                ts=(sudo -n tailscale --socket="$RUNNER_TEMP/darwin-tailscaled.sock")
                "''${ts[@]}" status || true
                "''${ts[@]}" netcheck || true
                # Attic skips paths already signed by upstream caches. Parallel
                # uploads help when per-connection throughput is the limit.
                xargs attic push -j 8 ${atticTarget} < "$RUNNER_TEMP/store-new.txt"
                echo "Pushed $count new paths to the private Darwin cache" >> "$GITHUB_STEP_SUMMARY"
              '';
              continue-on-error = true;
            }
            {
              name = "Push both closures to the private Darwin cache";
              id = "darwin_push";
              "if" = "steps.darwin_probe.outcome == 'success'";
              env = privateCacheEnv;
              run = ''
                python3 flake/actions/darwin-cache.py
                attic push -j 2 ${atticTarget} ./result-system ./result-home
                nix path-info --store ${attic.darwinStore} \
                  "$(readlink -f ./result-system)" "$(readlink -f ./result-home)"
                echo "Both Darwin closures are present in the private signed cache" >> "$GITHUB_STEP_SUMMARY"
              '';
              continue-on-error = true;
            }
            {
              name = "Upload cached deployment paths and provenance";
              "if" = "steps.darwin_push.outcome == 'success'";
              uses = "actions/upload-artifact@v4";
              "with" = {
                name = "darwin-\${{ inputs.target || 'L1' }}-\${{ github.sha }}";
                path = "deployment-paths.txt\nsource-revision.txt";
                if-no-files-found = "error";
                retention-days = 30;
              };
            }
            {
              name = "Encrypt both deployment closures";
              "if" = "steps.darwin_push.outcome != 'success'";
              env.ARTIFACT_RECIPIENT = "\${{ vars.CACHE_ARTIFACT_RECIPIENT }}";
              shell = "bash";
              run = ''
                set -euo pipefail
                rev=$(jq -r '.nodes["nixpkgs-2605"].locked.rev' flake.lock)
                # Expansion in the nested bash process is intentional.
                # shellcheck disable=SC2016
                nix shell "github:NixOS/nixpkgs/$rev#age" "github:NixOS/nixpkgs/$rev#zstd" --command bash -euo pipefail -c '
                  nix-store --query --requisites ./result-system ./result-home \
                    | sort -u | nix-store --export --stdin | zstd -T2 -3 \
                    | age -r "$ARTIFACT_RECIPIENT" -o deployment.nar.zst.age
                '
              '';
            }
            {
              name = "Disconnect the ephemeral Darwin runner";
              "if" = "always() && steps.darwin_credentials.outputs.enabled == 'true'";
              run = ''
                if command -v tailscale >/dev/null; then
                  sudo -n tailscale --socket="$RUNNER_TEMP/darwin-tailscaled.sock" logout
                fi
              '';
              continue-on-error = true;
            }
            {
              name = "Upload encrypted closures and provenance";
              "if" = "steps.darwin_push.outcome != 'success'";
              uses = "actions/upload-artifact@v4";
              "with" = {
                name = "darwin-\${{ inputs.target || 'L1' }}-\${{ github.sha }}";
                path = "deployment.nar.zst.age\ndeployment-paths.txt\nsource-revision.txt";
                if-no-files-found = "error";
                compression-level = 0;
                retention-days = 3;
              };
            }
          ];
        setup = builtins.filter (step:
          builtins.elem (step.id or "") ["darwin_credentials" "darwin_tailnet" "darwin_cache" "darwin_probe"]
          || builtins.elem step.name [
            "Require encrypted transport"
            "Checkout repo"
            "Install Nix"
            "Configure to use personal binary cache @ Cachix"
            "SSH-agent with auth for private repos"
            "Point local-checkout inputs at GitHub"
          ])
        originalSteps;
      in
        setup
        ++ [
          {
            name = "Measure native Darwin cache transport";
            "if" = "steps.darwin_probe.outcome == 'success'";
            env = privateCacheEnv;
            run = "python3 flake/actions/darwin-network-probe.py";
          }
          {
            name = "Disconnect the probe runner";
            "if" = "always() && steps.darwin_credentials.outputs.enabled == 'true'";
            run = ''
              if command -v tailscale >/dev/null; then
                sudo -n tailscale --socket="$RUNNER_TEMP/darwin-tailscaled.sock" logout
              fi
            '';
            continue-on-error = true;
          }
        ];
    };
  };
}
