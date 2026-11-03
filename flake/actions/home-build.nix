{
  attic-push,
  common-permissions,
  common-actions-cred,
  environment,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/home-build.yml" = {
    on = {
      push.tags = ["home*"];
    };
    jobs.build-home-manager-and-graph = {
      runs-on = "macos-15-intel";
      timeout-minutes = 150;
      permissions = common-permissions;
      inherit environment;
      steps =
        common-actions-cred
        ++ [
          {
            name = "Builds a home-manager configuration";
            run = "nix build --accept-flake-config .#homeConfigurations.L1.activationPackage --show-trace $LOCAL_OVERRIDES";
          }
          attic-push
          {
            name = "Generate home-manager dependency graph";
            run = "nix -vL run github:craigmbooth/nix-visualize -- --verbose --output ./assets/home_graph.png ./result";
          }
          {
            name = "Invert graph colors";
            run = "nix run nixpkgs#imagemagick -- convert ./assets/home_graph.png -channel RGB -negate +channel ./assets/home_graph.png";
          }
          {
            name = "Push to repo";
            run = ''
              git config --global user.name "GitHub Actions Bot"
              git config --global user.email bot@github.com
              git add .
              git commit -m "chore: update home-manager dependency graph" || echo "No changes to commit"
              git pull --rebase origin master
              git push origin master
            '';
            env = {
              GITHUB_TOKEN = "\${{ secrets.GITHUB_TOKEN }}";
            };
          }
        ];
    };
  };
}
