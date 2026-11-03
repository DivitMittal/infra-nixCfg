{
  self,
  lib,
  common-on,
  common-permissions,
  common-actions,
  environment,
  ...
}: let
  # Each configuration is evaluated on a runner of its own system: darwin
  # configs can import-from-derivation darwin-only sources, which a Linux
  # runner can't realise.
  runnerFor = {
    x86_64-linux = "ubuntu-latest";
    aarch64-linux = "ubuntu-24.04-arm";
    x86_64-darwin = "macos-15-intel";
    aarch64-darwin = "macos-latest";
  };

  targetsOf = kind: output:
    lib.attrsets.mapAttrsToList (name: cfg: let
      # Set by mkCfg via `// {hostSystem}`, which forces the config to WHNF; for
      # home-manager that runs its assertions, so a broken config would throw
      # here and empty the whole matrix. tryEval keeps it as a target (on the
      # default runner) so its own job reports the error.
      tried = builtins.tryEval (cfg.hostSystem or "x86_64-linux");
      system =
        if tried.success
        then tried.value
        else "x86_64-linux";
    in {
      attr = "${kind}.${name}.${output}";
      inherit system;
      runner = runnerFor.${system} or runnerFor.x86_64-linux;
    }) (self.${kind} or {});
in {
  # nix-on-droid configs are left out: evaluating them needs an aarch64-linux
  # proot-termux build that isn't cached anywhere.
  flake.evalTargets = lib.lists.concatLists [
    (targetsOf "nixosConfigurations" "config.system.build.toplevel")
    (targetsOf "darwinConfigurations" "system")
    (targetsOf "homeConfigurations" "activationPackage")
  ];

  flake.actions-nix.workflows.".github/workflows/eval.yml" = {
    on = common-on;
    jobs = {
      list-targets = {
        permissions = common-permissions;
        inherit environment;
        outputs.targets = "\${{ steps.targets.outputs.targets }}";
        steps =
          common-actions
          ++ [
            {
              name = "List configurations to evaluate";
              id = "targets";
              # Assign first: inside `echo "$(...)"` a failed eval is swallowed
              # and the step passes with an empty matrix.
              run = ''
                targets=$(nix eval --accept-flake-config --json .#.evalTargets $LOCAL_OVERRIDES)
                echo "targets=$targets" >> "$GITHUB_OUTPUT"
              '';
            }
          ];
      };
      evaluate = {
        name = "\${{ matrix.target.attr }}";
        needs = ["list-targets"];
        runs-on = "\${{ matrix.target.runner }}";
        permissions = common-permissions;
        inherit environment;
        strategy = {
          fail-fast = false;
          matrix.target = "\${{ fromJSON(needs.list-targets.outputs.targets) }}";
        };
        steps =
          common-actions
          ++ [
            {
              name = "Evaluate";
              # Leading `.` skips the packages.<system>/legacyPackages.<system>
              # prefix search, which would force every package's attr name.
              run = "nix eval --accept-flake-config --show-trace --raw .#.\${{ matrix.target.attr }}.drvPath $LOCAL_OVERRIDES";
            }
          ];
      };
    };
  };
}
