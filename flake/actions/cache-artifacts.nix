{...}: {
  _module.args.export-result = name: [
    {
      name = "Encrypt the build closure for LAN cache import";
      "if" = "steps.attic_push.outcome != 'success' && vars.CACHE_ARTIFACT_RECIPIENT != ''";
      env.ARTIFACT_RECIPIENT = "\${{ vars.CACHE_ARTIFACT_RECIPIENT }}";
      # Private input sources can be in the runtime closure. Encrypt before
      # uploading anything; the runner only receives L1's public recipient.
      run = ''
        rev=$(jq -r '.nodes["nixpkgs-2605"].locked.rev' flake.lock)
        nix shell "github:NixOS/nixpkgs/$rev#age" "github:NixOS/nixpkgs/$rev#zstd" --command bash -euo pipefail -c '
          nix-store --query --requisites ./result \
            | nix-store --export --stdin \
            | zstd -T0 -3 \
            | age -r "$ARTIFACT_RECIPIENT" -o result.nar.zst.age
        '
      '';
    }
    {
      name = "Upload the encrypted deployment closure";
      "if" = "steps.attic_push.outcome != 'success' && vars.CACHE_ARTIFACT_RECIPIENT != ''";
      uses = "actions/upload-artifact@v4";
      "with" = {
        name = "${name}-closure";
        path = "result.nar.zst.age";
        compression-level = 0;
        retention-days = 3;
      };
    }
  ];
}
