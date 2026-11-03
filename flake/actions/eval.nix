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
      # Set by mkCfg; reading it doesn't evaluate the config's modules.
      system = cfg.hostSystem or "x86_64-linux";
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
              run = ''echo "targets=$(nix eval --accept-flake-config --json .#evalTargets $LOCAL_OVERRIDES)" >> "$GITHUB_OUTPUT"'';
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
              run = "nix eval --accept-flake-config --show-trace --raw .#\${{ matrix.target.attr }}.drvPath $LOCAL_OVERRIDES";
            }
          ];
      };
    };
  };
}
