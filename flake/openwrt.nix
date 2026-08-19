{
  inputs,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: let
    uci = pkgs.callPackage "${inputs.openwrt-nix}/nix" {};
    mkRouter = wanMode:
      uci.writeUci (self.openwrtConfigurations.R1 {inherit inputs wanMode;});
    router = mkRouter "ont";
    androidTether = mkRouter "android-tether";
    wifiBackup = mkRouter "wifi-backup";

    # network/R1.age is a symlink to network/S1.age in OS-nixCfg-secrets — R1
    # and S1 intentionally share one admin password, one ciphertext.
    r1Secret = inputs.OS-nixCfg-secrets + "/secrets/network/R1.age";

    # WPA2 PSK for R0's own Wi-Fi (Airtel_anku_8585), used only by the
    # wifi-backup wanMode. A real external secret, not one we can generate —
    # encrypted at rest, decrypted here at deploy time, and injected onto R1
    # over SSH; it never touches the Nix store or the declarative UCI JSON.
    r1WifiPskSecret = inputs.OS-nixCfg-secrets + "/secrets/network/R1-wifi-psk.age";

    mkApp = {
      router,
      extraDeploy ? "",
    }: let
      nuci = "${uci.nuci}/bin/nuci";
      command = pkgs.writeShellScript "openwrt-router-deploy" ''
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
        # explicit -i it then refuses to fall back to agent-offered keys,
        # so we must point it at the deploy key file directly.
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
          password="$(${pkgs.rage}/bin/rage --decrypt -i "$identity" ${r1Secret})"
          printf '%s\n%s\n' "$password" "$password" \
            | "$ssh" "''${ssh_opts[@]}" "$target" passwd root
        }

        set_wifi_psk() {
          local identity psk
          identity="''${HOME}/.ssh/agenix/id_ed25519"
          [ -f "$identity" ] || {
            echo "missing agenix identity at $identity" >&2
            exit 1
          }
          psk="$(${pkgs.rage}/bin/rage --decrypt -i "$identity" ${r1WifiPskSecret})"
          printf '%s' "$psk" \
            | "$ssh" "''${ssh_opts[@]}" "$target" 'umask 077 && cat > /etc/nuci/wifi-psk'
        }

        case "$mode" in
          deploy)
            ${nuci} deploy "${router.json}" --target "$target" --identity "$deploy_identity" --watchdog-timeout 60
            set_root_password
            "$ssh" "''${ssh_opts[@]}" "$target" /etc/nuci/reconcile-apk-world apply
            ${extraDeploy}
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
      type = "app";
      program = toString command;
    };
  in {
    packages = {
      openwrt-ont-uci = router.json;
      openwrt-android-tether-uci = androidTether.json;
      openwrt-wifi-backup-uci = wifiBackup.json;
      openwrt-router-nuci = uci.nuci;
    };

    apps = {
      openwrt-ont = mkApp {inherit router;};
      openwrt-android-tether = mkApp {router = androidTether;};
      openwrt-wifi-backup = mkApp {
        router = wifiBackup;
        extraDeploy = "set_wifi_psk";
      };
    };
  };
}
