{
  common-permissions,
  common-actions-cred,
  environment,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/topology-build.yml" = {
    on = rec {
      push = {
        branches = ["master"];
        paths = [
          ## Global Topology configuration
          "topology/**"
          ## Flake topology module
          "flake/topology.nix"
          ## Host configurations
          "hosts/nixos/**"
        ];
      };
      pull_request = push;
      workflow_dispatch = {};
    };
    jobs.build-topology-and-commit = {
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions-cred
        ++ [
          {
            name = "Build topology visualization";
            run = "nix -vL build --accept-flake-config .#topology.x86_64-linux.config.output --show-trace $LOCAL_OVERRIDES";
          }
          {
            name = "Create assets directory for topology";
            run = "mkdir -p ./assets/topology";
          }
          {
            name = "Copy topology SVGs to assets";
            run = ''
              # Copy all generated SVG files
              cp -v result/*.svg ./assets/topology/ || true
              # List what was copied
              ls -lh ./assets/topology/
            '';
          }
          {
            name = "Commit topology visualizations";
            run = ''
              git config --global user.name "GitHub Actions Bot"
              git config --global user.email bot@github.com
              git add assets/topology/
              # Only commit if there are changes
              git diff --staged --quiet || git commit -m "chore: update topology visualizations"
              git push origin master || echo "No changes to push"
            '';
            env = {
              GITHUB_TOKEN = "\${{ secrets.GITHUB_TOKEN }}";
            };
          }
        ];
    };
  };
}
