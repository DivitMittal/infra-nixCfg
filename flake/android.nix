# nix-android — declarative Android/GrapheneOS device state over adb, run
# from a controller machine rather than mkCfg's droid class (which builds
# nix-on-droid's on-device Termux/proot environment instead). mkDevice's
# shape (system/modules/lockFile, no hostSpec/class layering) doesn't fit
# mkCfg's configGenerator switch, so it's wired directly here.
{inputs, ...}: {
  flake.androidConfigurations.M1 = inputs.nix-android.lib.mkDevice {
    system = "x86_64-darwin"; # L1 — the controller, not the phone
    modules = [../android/M1/device.nix];
    lockFile = ../android/M1/apps.lock.json;
  };

  perSystem = {
    system,
    pkgs,
    lib,
    ...
  }:
    lib.attrsets.optionalAttrs (system == "aarch64-darwin" || system == "x86_64-darwin") {
      # aarch64-darwin (ASL1) gets the CLI straight from upstream. nix-android's
      # own flake restricts its `systems` to x86_64-linux/aarch64-darwin, so
      # x86_64-darwin (L1) has no upstream package to alias — rebuild the same
      # `writeShellApplication` nix-android defines for itself, pointed at a
      # patched copy of its source (see nixAndroidSrc below), instead.
      packages.android-rebuild =
        if system == "aarch64-darwin"
        then inputs.nix-android.packages.aarch64-darwin.android-rebuild
        else let
          # The packaged CLI resolves `android-rebuild update`'s update-lock
          # builder as "$NIX_ANDROID_SRC#update-lock" — always against
          # nix-android's own flake, never the caller's — so on x86_64-darwin
          # that lookup fails unless nix-android's flake itself claims the
          # system. Patch just the `systems` list (flake-parts' sole gate on
          # which systems get perSystem outputs) rather than hand-duplicating
          # every packaged script nix-android ships, so `update` and
          # `suggest-sources` keep working if upstream adds more of them.
          # `"aarch64-darwin"` recurs elsewhere in the file (an internal
          # darwin-smoke device), so `0,/re/` restricts the edit to the first
          # match — the `systems` list — instead of a global replace; grep
          # afterwards turns a silent no-op (upstream reformatting that line)
          # into a loud build failure rather than a config that quietly never
          # supports x86_64-darwin.
          #
          # `${inputs.nix-android}` is the raw fetched source tree, not an
          # evaluation with our `nixpkgs.follows = "nixpkgs"` override applied
          # — that follows only rewires nix-android's already-evaluated flake
          # outputs (.lib/.packages/...), so its committed flake.lock still
          # carries its own pinned "nixpkgs_2" node (the top-level `nixpkgs`
          # input; verified via `.nodes.root.inputs.nixpkgs`), which has since
          # moved to a nixos-unstable revision that hard-drops x86_64-darwin.
          # Repoint that one node at nixpkgs-2605 — this repo's own
          # x86_64-darwin-safe branch — instead of snapshotting whatever
          # `inputs.nixpkgs` resolves to today, which would rot the same way.
          nixpkgs2605Node = pkgs.writeText "nixpkgs-2605-node.json" (builtins.toJSON {
            original = {
              type = "github";
              owner = "NixOS";
              repo = "nixpkgs";
              ref = "nixpkgs-26.05-darwin";
            };
            locked = {
              type = "github";
              owner = "NixOS";
              repo = "nixpkgs";
              inherit (inputs."nixpkgs-2605") rev narHash lastModified;
            };
          });
          nixAndroidSrc =
            pkgs.runCommand "nix-android-src-x86_64-darwin" {
              nativeBuildInputs = [pkgs.gnused pkgs.jq];
            } ''
              cp -r ${inputs.nix-android} "$out"
              chmod -R u+w "$out"

              sed -i '0,/"aarch64-darwin"/{s//"aarch64-darwin"\n        "x86_64-darwin"/}' "$out/flake.nix"
              grep -q '"x86_64-darwin"' "$out/flake.nix" || {
                echo "nix-android systems patch: no match found — upstream flake.nix likely changed" >&2
                exit 1
              }

              # The lock's "original" must match what flake.nix declares, or
              # Nix considers the lock stale and tries to auto-update it at
              # runtime — which then hard-fails with "Permission denied" since
              # the derivation output has already landed read-only in the
              # store by the time android-rebuild invokes it. Repoint the
              # declared URL to nixpkgs-26.05-darwin too, so it matches the
              # locked/original pair written into flake.lock below.
              grep -q 'nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"' "$out/flake.nix" || {
                echo "nix-android nixpkgs.url patch: no match found — upstream flake.nix likely changed" >&2
                exit 1
              }
              substituteInPlace "$out/flake.nix" --replace-fail \
                'nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";' \
                'nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";'

              jq -e '.nodes.nixpkgs_2' "$out/flake.lock" >/dev/null || {
                echo "nix-android nixpkgs lock patch: node 'nixpkgs_2' not found — upstream flake.lock structure likely changed" >&2
                exit 1
              }
              jq --slurpfile node ${nixpkgs2605Node} '.nodes.nixpkgs_2 = $node[0]' \
                "$out/flake.lock" > "$out/flake.lock.tmp"
              mv "$out/flake.lock.tmp" "$out/flake.lock"
            '';
        in
          pkgs.writeShellApplication {
            name = "android-rebuild";
            runtimeInputs = with pkgs; [
              android-tools
              coreutils
              curl
              gawk
              gnugrep
              gnused
              (python3.withPackages (p: [p.protobuf]))
              jq
            ];
            text = ''
              export NIX_ANDROID_SRC=${nixAndroidSrc}
              export NIX_ANDROID_BASH=${pkgs.bash}/bin/bash
              exec "$NIX_ANDROID_BASH" ${nixAndroidSrc}/scripts/android-rebuild.sh "$@"
            '';
          };
    };
}
