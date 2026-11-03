{
  common-on,
  common-permissions,
  common-actions,
  environment,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/flake-check.yml" = {
    on = common-on;
    jobs.checking-flake = {
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions
        ++ [
          {
            name = "Run nix flake check";
            run = "nix -vL flake check --all-systems --no-build $LOCAL_OVERRIDES";
          }
        ];
    };
  };
}
