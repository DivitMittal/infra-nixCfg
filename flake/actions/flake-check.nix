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
            run = "nix -vL flake check --all-systems --no-build";
          }
          {
            ## Nix test suites already fail during the eval above; the shell
            ## suites need a build.
            name = "Run shell tests";
            run = "nix -vL build --no-link .#checks.x86_64-linux.shellcheck .#checks.x86_64-linux.shell-tests";
          }
        ];
    };
  };
}
