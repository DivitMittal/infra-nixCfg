{
  inputs,
  lib,
  self,
  ...
}: let
  customLib = import ../lib/custom.nix {inherit lib;};
in {
  imports = [inputs.devshell.flakeModule];

  perSystem = {
    pkgs,
    config,
    ...
  }: let
    myFlakeInputs = lib.concatStringsSep " " [
      "OS-nixCfg-secrets"
      "Vim-Cfg"
      "Emacs-Cfg"
      "term-nixCfg"
      "firefox-nixCfg"
      "ai-nixCfg"
      "tidalcycles-nix"
      "hammerspoon-nix"
      "android-kvm"
      "brew-nix"
      "TLTR"
      "PKMS"
    ];
    uci = pkgs.callPackage "${inputs.openwrt-nix}/nix" {};
  in {
    devshells.default = {
      devshell = rec {
        name = "OS-nixCfg";
        motd = "{202}Welcome to {91}${name} {202}devshell!{reset} \n $(menu)";
        startup = {
          git-hooks.text = ''
            ${config.pre-commit.installationScript}
          '';
        };
        packages =
          lib.attrsets.attrValues {
            inherit
              (pkgs)
              ### LSPs & Formatters
              ## Nix
              nixd
              alejandra
              ## Kdl
              kdlfmt
              ## Shell
              shfmt
              ### Nix Tools
              # nix-visualize # (handled by GitHub Actions CI workflow)
              nvfetcher
              nixos-anywhere
              ### Android Tools
              android-tools
              ;
            ## AI context
            apm = customLib.mkUvxBin pkgs "apm" "--from apm-cli apm";
          }
          ++ [
            inputs.deploy-rs.packages.${pkgs.stdenvNoCC.hostPlatform.system}.default # Deploy-rs for remote deployment
            uci.nuci
          ];
      };
      commands = [
        {
          name = "bootstrap";
          help = "First-time setup for this machine; pass 'host' (default) or 'home'";
          command = "${self}/utils/bootstrap.sh \"$@\"";
          category = "bootstrap";
        }
        {
          name = "hms";
          help = "Rebuilds & switches the home-manager configuration (pass flags like -v --show-trace --impure)";
          command = "${self}/utils/home_rebuild.sh \"$@\"";
          category = "home-manager";
        }
        {
          name = "hts";
          help = "Rebuilds & switches the host configuration (pass flags like -v --show-trace --impure)";
          command = "${self}/utils/hosts_rebuild.sh \"$@\"";
          category = "hosts";
        }
        {
          name = "bootstrap-remote";
          help = "Remote first-install bootstrap for any NixOS host with nixos-anywhere";
          command = "${self}/utils/bootstrap_remote.sh \"$@\"";
          category = "bootstrap";
        }
        {
          name = "deploy-home";
          help = "Deploy a remote standalone Home Manager profile: deploy-home VPS1 [deploy-rs flags]";
          command = ''
            set -eu

            if [ "$#" -lt 1 ]; then
              echo "usage: deploy-home <host> [deploy-rs flags...]" >&2
              exit 2
            fi

            host="$1"
            shift

            deploy ".#''${host}-home" "$@"
          '';
          category = "home-manager";
        }
        {
          name = "m1-adb-forward";
          help = "Forward local SSH port 18022 to M1 nix-on-droid sshd over ADB";
          command = ''
            set -eu

            authorized_devices=$(adb devices | sed '1d' | awk '$2 == "device" {print $1}')
            adb_target=""

            if [ -n "''${ANDROID_SERIAL:-}" ]; then
              if ! printf '%s\n' "$authorized_devices" | grep -Fxq "$ANDROID_SERIAL"; then
                echo "ANDROID_SERIAL=$ANDROID_SERIAL is not an authorized ADB device." >&2
                adb devices >&2
                exit 1
              fi
              adb_target="-s $ANDROID_SERIAL"
            else
              device_count=$(printf '%s\n' "$authorized_devices" | grep -c . || true)
              if [ "$device_count" -eq 0 ]; then
                echo "No authorized ADB devices found." >&2
                adb devices >&2
                exit 1
              elif [ "$device_count" -gt 1 ]; then
                echo "Multiple authorized ADB devices found; set ANDROID_SERIAL to select M1." >&2
                adb devices >&2
                exit 1
              fi
            fi

            adb $adb_target forward tcp:18022 tcp:8022
            echo "Forwarded local tcp:18022 to M1 tcp:8022 over ADB."
            echo "Next: ssh M1-adb true"
            echo "Then: deploy .#M1-adb --dry-activate"
          '';
          category = "hosts";
        }
        {
          name = "m1-adb-unforward";
          help = "Remove the M1 ADB SSH port forward";
          command = "adb forward --remove tcp:18022";
          category = "hosts";
        }
        {
          name = "deploy-m1-adb";
          help = "Forward M1 SSH over ADB, verify SSH, then deploy .#M1-adb";
          command = ''
            set -eu

            m1-adb-forward
            ssh M1-adb true
            deploy .#M1-adb "$@"
          '';
          category = "hosts";
        }
        {
          name = "pkgs-update";
          help = "Update all custom package sources (pkgs/_sources/generated.nix) via nvfetcher";
          command = ''
            REPO_ROOT="''${DEVSHELL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
            GH_TOKEN=$(gh auth token 2>/dev/null)
            if [ -z "$GH_TOKEN" ]; then
              echo "Warning: no GitHub token found, you may hit rate limits. Run: gh auth login"
              nix run nixpkgs#nvfetcher -- build \
                -c "$REPO_ROOT/pkgs/nvfetcher.toml" \
                -o "$REPO_ROOT/pkgs/_sources" \
                "$@"
            else
              KEYFILE=$(mktemp /tmp/nvfetcher-key-XXXXXX.toml)
              echo -e "[keys]\ngithub = \"$GH_TOKEN\"" > "$KEYFILE"
              trap "rm -f $KEYFILE" EXIT
              nix run nixpkgs#nvfetcher -- build \
                -c "$REPO_ROOT/pkgs/nvfetcher.toml" \
                -o "$REPO_ROOT/pkgs/_sources" \
                -k "$KEYFILE" \
                "$@"
            fi
          '';
          category = "packages";
        }
        {
          name = "nfu";
          help = "Update all flake inputs, including nixpkgs (triggers full rebuild chain)";
          command = "nix flake update \"$@\"";
          category = "nix";
        }
        {
          name = "nfu-mine";
          help = "Update only DivitMittal-authored inputs — skips nixpkgs to avoid rebuild chain";
          command = "nix flake update ${myFlakeInputs}";
          category = "nix";
        }
        (lib.mkIf
          pkgs.stdenvNoCC.hostPlatform.isDarwin
          {
            name = "apps-backup";
            help = "Backup installed applications";
            command = ''
              REPO_DIR="''${DEVSHELL_ROOT:-$PWD}"
              BAK_DIR="$REPO_DIR/hosts/darwin/$(hostname)/programs/bak"
              [ -d "$BAK_DIR" ] || { echo "Backup directory doesn't exist: $BAK_DIR"; exit 1; }
              FILE="$BAK_DIR/apps_$(date +%b%y).txt"
              /usr/bin/env ls /Applications/ 1> "$FILE"
              /usr/bin/env ls "$HOME/Applications/Home Manager Apps/" 1>> "$FILE"
            '';
            category = "misc";
          })
      ];
    };
  };
}
