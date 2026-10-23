{
  inputs,
  self,
  ...
}: {
  # Declarative nuci deploy for T640, the OpenWrt/ImmortalWrt guest VM that
  # hosts/nixos/T1/router-vm.nix boots on T1 — mirrors flake/openwrt.nix's
  # R1 pattern (uci.writeUci + a `nuci deploy` app), adapted for T640's
  # single config (no wanMode variants: T640 always runs the multi-PPPoE
  # config from hosts/openwrt/T640/modules/network.nix; the DMZ-fallback
  # path documented in hosts/README.md is a live `uci` reconfiguration, not
  # a separate declarative variant).
  #
  # This app is deliberately image-flavor-agnostic: the same UCI JSON
  # deploys onto either `openwrt-t640-router` or `immortalwrt-t640-router`
  # (flake/openwrt-images.nix's imagebuilder outputs) — the split there is
  # imagebuilder = minimal bootable base + baked packages, nuci (here) = all
  # ongoing declarative config, same explanation as hosts/README.md.
  perSystem = {pkgs, ...}: let
    uci = pkgs.callPackage "${inputs.openwrt-nix}/nix" {};
    router = uci.writeUci (self.openwrtConfigurations.T640 {inherit inputs;});

    # network/T640.age does not exist yet in infra-nixCfg-secrets as of this
    # branch — create it there (ragenix -e secrets/network/T640.age) before
    # the first real `nix run .#t640-router` deploy, same convention as
    # R1's r1Secret (flake/openwrt.nix).
    t640Secret = inputs.infra-nixCfg-secrets + "/secrets/network/T640.age";

    # Real per-line PPPoE username+password, one two-line ("username\n
    # password") secret file per line — same reasoning as R1's
    # r1WifiPskSecret: a real external secret we can't generate, decrypted
    # here at deploy time and injected onto T640 over SSH; it never touches
    # the Nix store or the declarative UCI JSON (which only ever contains
    # the CHANGEME placeholders from hosts/openwrt/T640/modules/network.nix).
    # Neither secret exists yet in infra-nixCfg-secrets — create both
    # (secrets/network/T640-wan1.age, secrets/network/T640-wan2.age) before
    # the first real deploy.
    t640Wan1Secret = inputs.infra-nixCfg-secrets + "/secrets/network/T640-wan1.age";
    t640Wan2Secret = inputs.infra-nixCfg-secrets + "/secrets/network/T640-wan2.age";

    nuci = "${uci.nuci}/bin/nuci";
    command = pkgs.writeShellScript "openwrt-t640-router-deploy" ''
      set -eu

      if [ "$#" -eq 0 ]; then
        exec ${router.command}
      fi

      target="$1"
      mode="''${2:-deploy}"
      ssh=${pkgs.openssh}/bin/ssh
      ssh_opts=(
        -o StrictHostKeyChecking=no
        -o BatchMode=yes
        -o UserKnownHostsFile=/dev/null
      )

      # nuci's deploy transport hardcodes IdentitiesOnly=yes; without an
      # explicit -i it then refuses to fall back to agent-offered keys, so
      # we must point it at the deploy key file directly.
      deploy_identity="''${OPENWRT_SSH_IDENTITY:-''${HOME}/.ssh/github/id_ed25519}"
      [ -f "$deploy_identity" ] || {
        echo "missing SSH deploy identity at $deploy_identity (override with OPENWRT_SSH_IDENTITY)" >&2
        exit 1
      }

      set_root_password() {
        local identity password
        identity="''${HOME}/.ssh/agenix/id_ed25519"
        [ -f "$identity" ] || {
          echo "missing agenix identity at $identity" >&2
          exit 1
        }
        password="$(${pkgs.rage}/bin/rage --decrypt -i "$identity" ${t640Secret})"
        printf '%s\n%s\n' "$password" "$password" \
          | "$ssh" "''${ssh_opts[@]}" "$target" passwd root
      }

      set_wan_credentials() {
        local identity
        identity="''${HOME}/.ssh/agenix/id_ed25519"
        [ -f "$identity" ] || {
          echo "missing agenix identity at $identity" >&2
          exit 1
        }
        ${pkgs.rage}/bin/rage --decrypt -i "$identity" ${t640Wan1Secret} \
          | "$ssh" "''${ssh_opts[@]}" "$target" 'umask 077 && cat > /etc/nuci/wan1-credentials'
        ${pkgs.rage}/bin/rage --decrypt -i "$identity" ${t640Wan2Secret} \
          | "$ssh" "''${ssh_opts[@]}" "$target" 'umask 077 && cat > /etc/nuci/wan2-credentials'
      }

      case "$mode" in
        deploy)
          ${nuci} deploy "${router.json}" --target "$target" --identity "$deploy_identity" --watchdog-timeout 60
          set_root_password
          set_wan_credentials
          "$ssh" "''${ssh_opts[@]}" "$target" /etc/nuci/reconcile-apk-world apply
          "$ssh" "''${ssh_opts[@]}" "$target" /etc/nuci/reconcile-services
          ;;
        --check-apk-world)
          "$ssh" "''${ssh_opts[@]}" "$target" /etc/nuci/reconcile-apk-world check
          ;;
        *)
          echo "Usage: $0 [target [--check-apk-world]]" >&2
          exit 2
          ;;
      esac
    '';
  in {
    packages = {
      t640-router-uci = router.json;
      t640-router-nuci = uci.nuci;
    };

    apps.t640-router = {
      type = "app";
      program = toString command;
    };
  };
}
