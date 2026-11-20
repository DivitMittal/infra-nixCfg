{
  self,
  lib,
  common-on,
  common-permissions,
  common-actions,
  environment,
  attic,
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
    # Besides PRs/master: pushing any `eval/**` branch evaluates that commit on
    # native runners without opening a PR (how agents should evaluate instead
    # of building locally), and workflow_dispatch can run it on demand.
    on =
      common-on
      // {
        push = common-on.push // {branches = ["master" "eval/**"];};
        workflow_dispatch.inputs.filter = {
          description = "Regex on target attrs (e.g. 'homeConfigurations\\.(L1|ASL1)\\.'); empty = all";
          required = false;
          type = "string";
          default = "";
        };
      };
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
              # Selection, first match wins:
              #   1. the dispatch input or an `Eval-Filter: <regex>` trailer on
              #      the head commit (manual override);
              #   2. on pull requests, the targets the changed files can affect
              #      (flake/actions/select-targets.sh), possibly none;
              #   3. everything (pushes to master, eval/** without a trailer).
              # Values reach the shell via env/git only, never interpolated into
              # the script.
              env = {
                FILTER_INPUT = "\${{ inputs.filter }}";
                EVENT_NAME = "\${{ github.event_name }}";
                BASE_SHA = "\${{ github.event.pull_request.base.sha }}";
              };
              # Assign first: inside `echo "$(...)"` a failed eval is swallowed
              # and the step passes with an empty matrix.
              run = ''
                filter=''${FILTER_INPUT:-$(git log -1 --format='%(trailers:key=Eval-Filter,valueonly,separator=|)')}
                source=manual
                if [ -z "$filter" ] && [ "$EVENT_NAME" = pull_request ]; then
                  git fetch --quiet --depth=1 origin "$BASE_SHA"
                  changed=$(git diff --name-only "$BASE_SHA" HEAD)
                  echo "changed files:"; sed 's/^/  /' <<<"$changed"
                  selected=$(bash flake/actions/select-targets.sh <<<"$changed")
                  if [ -z "$selected" ]; then
                    echo "No evaluated configuration depends on these changes."
                    echo "targets=[]" >> "$GITHUB_OUTPUT"
                    exit 0
                  fi
                  [ "$selected" = ALL ] || { filter=$selected; source=changes; }
                fi
                all=$(nix eval --accept-flake-config --json .#.evalTargets $LOCAL_OVERRIDES)
                targets=$(jq -c --arg f "$filter" 'map(select(.attr | test($f)))' <<<"$all")
                echo "filter ($source): ''${filter:-<none>}"
                jq -r '.[].attr' <<<"$targets"
                if [ "$(jq length <<<"$targets")" -eq 0 ]; then
                  echo "::error::Eval filter '$filter' matched no targets"
                  exit 1
                fi
                echo "targets=$targets" >> "$GITHUB_OUTPUT"
              '';
            }
          ];
      };
      evaluate = {
        name = "\${{ matrix.target.attr }}";
        needs = ["list-targets"];
        # A PR whose changes no configuration depends on selects nothing; an
        # empty matrix would fail the workflow instead of skipping.
        "if" = "needs.list-targets.outputs.targets != '[]'";
        runs-on = "\${{ matrix.target.runner }}";
        permissions = common-permissions;
        inherit environment;
        # Builds on master can take a while on a cold cache.
        timeout-minutes = 300;
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
            {
              # On master, build whatever the attic cache on T3 doesn't have
              # yet and push it, so hosts download instead of compiling.
              # Checking the output path first avoids downloading an
              # already-cached closure. Off until the attic secrets exist.
              name = "Build and cache";
              "if" = "github.event_name == 'push' && github.ref == 'refs/heads/master' && runner.os != 'macOS' && steps.attic_setup.outcome == 'success'";
              env.ATTR = "\${{ matrix.target.attr }}";
              run = ''
                out=$(nix eval --accept-flake-config --raw ".#.$ATTR.outPath" $LOCAL_OVERRIDES)
                if nix path-info --store "${attic.store}" "$out" >/dev/null 2>&1; then
                  echo "already cached: $out"
                  exit 0
                fi
                if [ "$RUNNER_OS" = Linux ]; then
                  sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL
                fi
                nix build --accept-flake-config --no-link ".#.$ATTR" $LOCAL_OVERRIDES
                attic push ${attic.remote}:${attic.cache} "$out"
              '';
            }
          ];
      };
    };
  };
}
