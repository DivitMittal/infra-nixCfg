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
        group = "darwin-offload-\${{ inputs.target || 'L1' }}";
        cancel-in-progress = true;
      };
      runs-on = "\${{ inputs.target == 'ASL1' && 'macos-15' || 'macos-15-intel' }}";
      timeout-minutes = 360;
      permissions.contents = "read";
      inherit environment;
      steps =
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
            uses = "tailscale/github-action@v4";
            "with" = {
              oauth-client-id = "\${{ secrets.TS_OAUTH_CLIENT_ID }}";
              oauth-secret = "\${{ secrets.TS_OAUTH_SECRET }}";
              tags = "tag:ci";
              args = "--accept-routes --accept-dns=false";
            };
            continue-on-error = true;
          }
          {
            name = "Use only the private pinned Darwin cache";
            id = "darwin_cache";
            "if" = "steps.darwin_tailnet.outcome == 'success'";
            env = privateCacheEnv;
            run = ''
              rev=$(jq -r '.nodes["nixpkgs-2605"].locked.rev' flake.lock)
              nix profile install "github:NixOS/nixpkgs/$rev#attic-client"
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
            env.TARGET = "\${{ inputs.target || 'L1' }}";
            shell = "bash";
            run = ''
              set -euo pipefail
              case "$TARGET" in
                L1) test "$(uname -m)" = x86_64 ;;
                ASL1) test "$(uname -m)" = arm64 ;;
                *) echo "Unsupported target" >&2; exit 1 ;;
              esac
              read -r -a local_overrides <<< "$LOCAL_OVERRIDES"
              nix build --accept-flake-config --no-write-lock-file --max-jobs 2 --cores 2 --option fallback true \
                ".#darwinConfigurations.$TARGET.system" --out-link result-system "''${local_overrides[@]}"
              nix build --accept-flake-config --no-write-lock-file --max-jobs 2 --cores 2 --option fallback true \
                ".#homeConfigurations.$TARGET.activationPackage" --out-link result-home "''${local_overrides[@]}"
              readlink -f result-system > deployment-paths.txt
              readlink -f result-home >> deployment-paths.txt
              printf '%s\n' "$GITHUB_SHA" > source-revision.txt
            '';
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
    };
  };
}
