{
  attic-push,
  common-permissions,
  environment,
  common-actions,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/nixos-build.yml" = {
    on = {
      push.tags = ["host*"];
    };
    jobs.build-nixos-configuration = {
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions
        ++ [
          {
            name = "Builds a nixos configuration";
            run = "nix -vL build --accept-flake-config .#nixosConfigurations.WSL.config.system.build.toplevel --show-trace $LOCAL_OVERRIDES";
          }
          attic-push
        ];
    };
  };
}
