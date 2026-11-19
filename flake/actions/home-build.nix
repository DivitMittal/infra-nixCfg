{
  attic-push,
  export-result,
  common-permissions,
  common-actions-cred,
  environment,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/home-build.yml" = {
    on = {
      workflow_dispatch = {};
      push.tags = ["home*"];
    };
    jobs.build-home-manager-and-graph = {
      runs-on = "macos-15-intel";
      timeout-minutes = 360;
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions-cred
        ++ [
          {
            name = "Builds a home-manager configuration";
            shell = "bash";
            run = ''
              set -euo pipefail
              nix build --accept-flake-config --print-out-paths .#.homeConfigurations.L1.activationPackage --show-trace $LOCAL_OVERRIDES | tee build-result.txt
              test -s build-result.txt
              test -e ./result
              echo "Built $(cat build-result.txt) from $GITHUB_SHA" >> "$GITHUB_STEP_SUMMARY"
            '';
          }
          attic-push
          {
            name = "Record the deployment store path";
            uses = "actions/upload-artifact@v4";
            "with" = {
              name = "home-manager-L1";
              path = "build-result.txt";
              retention-days = 7;
            };
          }
        ]
        ++ export-result "home-manager-L1"
        ++ [
          {
            name = "Generate home-manager dependency graph";
            "if" = "github.event_name == 'push'";
            run = "nix -vL run github:craigmbooth/nix-visualize -- --verbose --output ./assets/home_graph.png ./result";
          }
          {
            name = "Invert graph colors";
            "if" = "github.event_name == 'push'";
            run = "nix run nixpkgs#imagemagick -- convert ./assets/home_graph.png -channel RGB -negate +channel ./assets/home_graph.png";
          }
          {
            name = "Push to repo";
            "if" = "github.event_name == 'push'";
            run = ''
              git config --global user.name "GitHub Actions Bot"
              git config --global user.email bot@github.com
              git add assets/home_graph.png
              git commit -m "chore: update home-manager dependency graph" || echo "No changes to commit"
              git pull --rebase origin master
              git push origin master
            '';
            env = {
              GITHUB_TOKEN = "\${{ secrets.GITHUB_TOKEN }}";
            };
          }
        ];
    };
  };
}
