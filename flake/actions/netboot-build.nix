{
  common-permissions,
  common-post-actions,
  ...
}: {
  # Builds the t1-netboot PXE bundle (kernel, initrd, iPXE binaries + script;
  # flake/netboot.nix) on a Linux runner and uploads it as an artifact, so a
  # Mac on the LAN can serve it with `nix run .#pxe-serve-darwin`. The push
  # trigger lets it run from a feature branch, since workflow_dispatch only
  # works once the workflow is on the default branch.
  flake.actions-nix.workflows.".github/workflows/netboot-build.yml" = {
    on = {
      workflow_dispatch = {};
      push.paths = [
        "flake/netboot.nix"
        "hosts/netboot/**"
        "common/hosts/netboot/**"
      ];
    };
    jobs.build-netboot-bundle = {
      permissions = common-permissions;
      steps =
        [
          {
            name = "Checkout repo";
            uses = "actions/checkout@main";
            "with" = {
              fetch-depth = 1;
              persist-credentials = false;
            };
          }
        ]
        ++ common-post-actions
        ++ [
          {
            name = "Build netboot bundle";
            run = ''
              nix -vL build --accept-flake-config .#netboot-bundle --show-trace -o result $LOCAL_OVERRIDES
              # upload-artifact doesn't follow a symlinked store directory
              cp -rL result t1-netboot-bundle
              ls -lh t1-netboot-bundle
            '';
          }
          {
            name = "Upload bundle";
            uses = "actions/upload-artifact@v4";
            "with" = {
              name = "t1-netboot-bundle";
              path = "t1-netboot-bundle";
              retention-days = 14;
              compression-level = 0; # the initrd is already compressed
            };
          }
        ];
    };
  };
}
