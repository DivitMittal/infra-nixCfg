{
  attic-push,
  common-permissions,
  common-actions,
  environment,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/darwin-build.yml" = {
    on = {
      push.tags = ["host*"];
    };
    jobs.build-nix-darwin-configuration = {
      runs-on = "macos-15-intel";
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions
        ++ [
          {
            name = "Builds a nix-darwin configuration";
            run = "nix -vL build --accept-flake-config .#darwinConfigurations.L1.config.system.build.toplevel --show-trace $LOCAL_OVERRIDES";
          }
          attic-push
        ];
    };
  };
}
