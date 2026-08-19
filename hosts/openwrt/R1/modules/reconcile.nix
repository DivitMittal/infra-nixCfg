{config, ...}: let
  excludedBasePackages = [
    "luci"
    "luci-app-attendedsysupgrade"
    "luci-app-firewall"
    "luci-app-package-manager"
    "luci-base"
    "luci-lib-uqr"
    "luci-light"
    "luci-mod-admin-full"
    "luci-mod-network"
    "luci-mod-status"
    "luci-mod-system"
    "luci-proto-ipv6"
    "luci-proto-ppp"
    "luci-ssl"
    "luci-theme-bootstrap"
    "uhttpd"
    "uhttpd-mod-ubus"
  ];
  declaredPackageLines = builtins.concatStringsSep "\n" config.uci.packages;
  excludedBasePackageLines = builtins.concatStringsSep "\n" excludedBasePackages;
in {
  uci.files = [
    {
      path = "/etc/nuci/reconcile-apk-world";
      executable = true;
      content = ''
        #!/bin/sh
        set -eu

        mode="''${1:-apply}"
        base_world=/rom/etc/apk/world
        live_world=/etc/apk/world
        desired_world="$(mktemp /tmp/nuci-apk-world.XXXXXX)"
        backup_world="$(mktemp /tmp/nuci-apk-world-backup.XXXXXX)"
        excluded_world="$(mktemp /tmp/nuci-apk-world-excluded.XXXXXX)"

        cleanup() {
          rm -f "$desired_world" "$backup_world" "$excluded_world"
        }
        trap cleanup EXIT INT TERM HUP

        [ -r "$base_world" ] || {
          echo "Cannot reconcile APK world: $base_world is unavailable" >&2
          exit 1
        }
        [ -r "$live_world" ] || {
          echo "Cannot reconcile APK world: $live_world is unavailable" >&2
          exit 1
        }

        cat > "$excluded_world" <<'NUCI_EXCLUDED_PACKAGES'
        ${excludedBasePackageLines}
        NUCI_EXCLUDED_PACKAGES

        {
          while IFS= read -r package; do
            grep -Fqx "$package" "$excluded_world" || echo "$package"
          done < "$base_world"
          cat <<'NUCI_PACKAGES'
        ${declaredPackageLines}
        NUCI_PACKAGES
        } | sed '/^[[:space:]]*$/d' | sort -u > "$desired_world"

        if cmp -s "$desired_world" "$live_world"; then
          echo "APK world is already reconciled."
          exit 0
        fi

        echo "APK world drift:"
        while IFS= read -r package; do
          grep -Fqx "$package" "$desired_world" || echo "  - $package"
        done < "$live_world"
        while IFS= read -r package; do
          grep -Fqx "$package" "$live_world" || echo "  + $package"
        done < "$desired_world"

        case "$mode" in
          check)
            exit 1
            ;;
          apply)
            cp "$live_world" "$backup_world"
            cp "$desired_world" "$live_world"
            if ! apk fix --simulate; then
              echo "APK cannot solve the desired world; restoring the previous world" >&2
              cp "$backup_world" "$live_world"
              exit 1
            fi
            if ! apk fix; then
              echo "APK reconciliation failed; restoring the previous world" >&2
              cp "$backup_world" "$live_world"
              apk fix || true
              exit 1
            fi
            cmp -s "$desired_world" "$live_world" || {
              echo "APK changed the world unexpectedly" >&2
              exit 1
            }
            echo "APK world reconciled."
            ;;
          *)
            echo "Usage: $0 [apply|check]" >&2
            exit 2
            ;;
        esac
      '';
    }
    {
      path = "/etc/nuci/reconcile-services";
      executable = true;
      content = ''
        #!/bin/sh
        set -eu

        for hook in /etc/nuci/reconcile.d/*; do
          [ -x "$hook" ] || continue
          "$hook"
        done
      '';
    }
  ];
}
