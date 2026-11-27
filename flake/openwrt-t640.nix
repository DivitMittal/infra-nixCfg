{
  inputs,
  self,
  ...
}: {
  # Declarative nuci deploy for T640, the OpenWrt/ImmortalWrt guest VM that
  # hosts/nixos/T1/router-vm.nix boots on T1 — mirrors flake/openwrt.nix's
  # R1 pattern (uci.writeUci + a `nuci deploy` app), with one app per WAN
  # mode (hosts/openwrt/T640/modules/network.nix): `t640-router` for DMZ
  # behind R0, `t640-router-pppoe` for two PPPoE lines with R0 bridged.
  #
  # This app is deliberately image-flavor-agnostic: the same UCI JSON
  # deploys onto either `openwrt-t640-router` or `immortalwrt-t640-router`
  # (flake/openwrt-images.nix's imagebuilder outputs) — the split there is
  # imagebuilder = minimal bootable base + baked packages, nuci (here) = all
  # ongoing declarative config, same explanation as hosts/README.md.
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    uci = pkgs.callPackage "${inputs.openwrt-nix}/nix" {};
    mkRouter = wanMode:
      uci.writeUci (self.openwrtConfigurations.T640 {inherit inputs wanMode;});
    dmzRouter = mkRouter "dmz";
    pppoeRouter = mkRouter "pppoe";

    # Router root password (generated, not a human-chosen one).
    t640Secret = inputs.infra-nixCfg-secrets + "/secrets/network/T640.age";

    # Real per-line PPPoE username+password, one two-line ("username\n
    # password") secret file per line — same reasoning as R1's
    # r1WifiPskSecret: a real external secret we can't generate, decrypted
    # here at deploy time and injected onto T640 over SSH; it never touches
    # the Nix store or the declarative UCI JSON (which only ever contains
    # the CHANGEME placeholders from hosts/openwrt/T640/modules/network.nix).
    # One file per line that exists in infra-nixCfg-secrets
    # (secrets/network/T640-wanN.age); the router's PPPoE line count must
    # match (pppoeLines in hosts/openwrt/T640/modules/network.nix).
    t640WanSecrets = builtins.filter (x: builtins.pathExists x.file) (map (n: {
      inherit n;
      file = inputs.infra-nixCfg-secrets + "/secrets/network/T640-wan${toString n}.age";
    }) [1 2]);

    nuci = "${uci.nuci}/bin/nuci";
    mkCommand = {
      router,
      withPppoe,
    }:
      pkgs.writeShellScript "openwrt-t640-router-deploy" ''
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
          ${lib.concatMapStringsSep "\n" (w: ''
            ${pkgs.rage}/bin/rage --decrypt -i "$identity" ${w.file} \
              | "$ssh" "''${ssh_opts[@]}" "$target" 'umask 077 && cat > /etc/nuci/wan${toString w.n}-credentials'
          '')
          t640WanSecrets}
        }

        case "$mode" in
          deploy)
            ${nuci} deploy "${router.json}" --target "$target" --identity "$deploy_identity" --watchdog-timeout 60
            set_root_password
            ${lib.optionalString withPppoe "set_wan_credentials"}
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
      t640-router-uci = dmzRouter.json;
      t640-router-pppoe-uci = pppoeRouter.json;
      t640-router-nuci = uci.nuci;
    };

    # `nix run .#t640-router <target>`: DMZ mode (R0 forwards to a static WAN).
    # `nix run .#t640-router-pppoe <target>`: once R0 is bridged and the
    # T640-wan{1,2}.age PPPoE secrets exist.
    apps = {
      t640-router = {
        type = "app";
        program = toString (mkCommand {
          router = dmzRouter;
          withPppoe = false;
        });
      };
      t640-router-pppoe = {
        type = "app";
        program = toString (mkCommand {
          router = pppoeRouter;
          withPppoe = true;
        });
      };
    };
  };
}
