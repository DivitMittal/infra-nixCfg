{
  attic-push,
  common-permissions,
  common-actions,
  environment,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/darwin-build.yml" = {
    on = {
      workflow_dispatch = {};
      push.tags = ["host*"];
    };
    jobs.build-nix-darwin-configuration = {
      runs-on = "macos-15-intel";
      timeout-minutes = 360;
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions
        ++ [
          {
            name = "Builds a nix-darwin configuration";
            run = ''
              nix build --accept-flake-config --print-out-paths .#.darwinConfigurations.L1.system --show-trace $LOCAL_OVERRIDES | tee build-result.txt
              echo "Built $(cat build-result.txt) from $GITHUB_SHA" >> "$GITHUB_STEP_SUMMARY"
            '';
          }
          attic-push
          {
            name = "Record the deployment store path";
            uses = "actions/upload-artifact@v4";
            "with" = {
              name = "nix-darwin-L1";
              path = "build-result.txt";
              retention-days = 7;
            };
          }
        ];
    };
  };
}
