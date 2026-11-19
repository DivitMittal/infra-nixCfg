# Explicit build-only offload. Private closures leave the runner encrypted.
{
  common-actions,
  environment,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/darwin-offload.yml" = {
    on.workflow_dispatch.inputs.target = {
      description = "Intel Darwin target (build only)";
      type = "choice";
      options = ["L1" "ASL1"];
      default = "L1";
      required = true;
    };
    jobs.build = {
      runs-on = "macos-15-intel";
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
        # Magic cache uploads and Attic publishing require a separate privacy
        # review. Keep private source paths out of shared Actions caches too.
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
            name = "Build on native Intel Darwin";
            env.TARGET = "\${{ inputs.target }}";
            shell = "bash";
            run = ''
              set -euo pipefail
              case "$TARGET" in L1|ASL1) ;; *) echo "Unsupported target" >&2; exit 1 ;; esac
              test "$(uname -m)" = x86_64
              read -r -a local_overrides <<< "$LOCAL_OVERRIDES"
              nix build --accept-flake-config --no-write-lock-file --max-jobs 2 --cores 2 \
                ".#.darwinConfigurations.$TARGET.system" --out-link result-system "''${local_overrides[@]}"
              nix build --accept-flake-config --no-write-lock-file --max-jobs 2 --cores 2 \
                ".#.homeConfigurations.$TARGET.activationPackage" --out-link result-home "''${local_overrides[@]}"
            '';
          }
          {
            name = "Encrypt both deployment closures";
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
              readlink -f result-system > deployment-paths.txt
              readlink -f result-home >> deployment-paths.txt
              printf '%s\n' "$GITHUB_SHA" > source-revision.txt
            '';
          }
          {
            name = "Upload encrypted closures and provenance";
            uses = "actions/upload-artifact@v4";
            "with" = {
              name = "darwin-\${{ inputs.target }}-\${{ github.sha }}";
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
