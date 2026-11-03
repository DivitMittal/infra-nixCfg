{
  common-permissions,
  common-post-actions,
  ...
}: {
  flake.actions-nix.workflows.".github/workflows/iso-release.yml" = {
    on = {
      push = {
        tags = ["iso*"];
      };
    };
    jobs.build-and-release-iso = {
      permissions =
        common-permissions
        // {
          contents = "write";
        };
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
            name = "Build iso";
            run = "nix -vL build --accept-flake-config .#nixosConfigurations.iso.config.system.build.isoImage --show-trace -o result-iso $LOCAL_OVERRIDES";
          }
          {
            name = "Build t2-iso";
            run = "nix -vL build --accept-flake-config .#nixosConfigurations.t2-iso.config.system.build.isoImage --show-trace -o result-t2-iso $LOCAL_OVERRIDES";
          }
          {
            name = "Upload iso to Cloudflare R2";
            run = ''
              ISO_FILE=$(find result-iso/iso -name "*.iso" | head -1)
              ISO_NAME=$(basename "$ISO_FILE")
              aws s3 cp "$ISO_FILE" "s3://$R2_BUCKET/''${GITHUB_REF_NAME}/$ISO_NAME" \
                --endpoint-url "https://''${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
            '';
            env = {
              AWS_ACCESS_KEY_ID = "\${{ secrets.R2_ACCESS_KEY_ID }}";
              AWS_SECRET_ACCESS_KEY = "\${{ secrets.R2_SECRET_ACCESS_KEY }}";
              R2_ACCOUNT_ID = "\${{ secrets.R2_ACCOUNT_ID }}";
              R2_BUCKET = "\${{ secrets.R2_BUCKET }}";
            };
          }
          {
            name = "Upload t2-iso to Cloudflare R2";
            run = ''
              ISO_FILE=$(find result-t2-iso/iso -name "*.iso" | head -1)
              ISO_NAME=$(basename "$ISO_FILE")
              aws s3 cp "$ISO_FILE" "s3://$R2_BUCKET/''${GITHUB_REF_NAME}/$ISO_NAME" \
                --endpoint-url "https://''${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
            '';
            env = {
              AWS_ACCESS_KEY_ID = "\${{ secrets.R2_ACCESS_KEY_ID }}";
              AWS_SECRET_ACCESS_KEY = "\${{ secrets.R2_SECRET_ACCESS_KEY }}";
              R2_ACCOUNT_ID = "\${{ secrets.R2_ACCOUNT_ID }}";
              R2_BUCKET = "\${{ secrets.R2_BUCKET }}";
            };
          }
          {
            # Requires binfmt_misc + QEMU on the runner, or a native aarch64 builder.
            # Register emulation: nix.settings.extra-platforms = ["aarch64-linux"];
            name = "Build as-iso";
            run = "nix -vL build --accept-flake-config .#nixosConfigurations.as-iso.config.system.build.isoImage --show-trace -o result-as-iso $LOCAL_OVERRIDES";
          }
          {
            name = "Upload as-iso to Cloudflare R2";
            run = ''
              ISO_FILE=$(find result-as-iso/iso -name "*.iso" | head -1)
              ISO_NAME=$(basename "$ISO_FILE")
              aws s3 cp "$ISO_FILE" "s3://$R2_BUCKET/''${GITHUB_REF_NAME}/$ISO_NAME" \
                --endpoint-url "https://''${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
            '';
            env = {
              AWS_ACCESS_KEY_ID = "\${{ secrets.R2_ACCESS_KEY_ID }}";
              AWS_SECRET_ACCESS_KEY = "\${{ secrets.R2_SECRET_ACCESS_KEY }}";
              R2_ACCOUNT_ID = "\${{ secrets.R2_ACCOUNT_ID }}";
              R2_BUCKET = "\${{ secrets.R2_BUCKET }}";
            };
          }
        ];
    };
  };
}
