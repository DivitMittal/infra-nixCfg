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
            # Not `--all-systems --no-build`: --no-build runs read-only, so drv
            # and source paths are never written and anything needing their
            # references fails "path ... is not valid" (NixOS/nix#15448; hit by
            # apps.<system>.tty). Other systems are covered by eval.yml, which
            # evaluates every configuration on its own native runner.
            name = "Run nix flake check";
            run = "nix -vL flake check $LOCAL_OVERRIDES";
          }
        ];
    };
  };
}
