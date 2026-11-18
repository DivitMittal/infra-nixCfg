# Wired networking for the compute t640s (T2, T3). Not T1: its NICs belong to
# the router VM, and bouncing them would take the home network down.
{
  lib,
  pkgs,
  ...
}: let
  # On 2026-11-18 T3's onboard RTL8168ep lost carrier mid-transfer and never
  # retrained until a power cycle; no tx timeout or driver error was logged.
  # This recovers a stuck PHY without someone at the box: bounce the link,
  # and if that doesn't bring carrier back, rebind the PCI device.
  watchdog = pkgs.writeShellApplication {
    name = "wired-link-watchdog";
    runtimeInputs = [pkgs.iproute2 pkgs.coreutils];
    text = ''
      interval=10
      grace=30       # seconds without carrier before acting
      backoff=300    # wait after a full recovery attempt, so an unplugged cable isn't hammered

      # The onboard r8169 port: physical, ethernet, bound to that driver.
      pick() {
        for n in /sys/class/net/*; do
          [ -e "$n/device/driver" ] || continue
          [ "$(basename "$(readlink -f "$n/device/driver")")" = r8169 ] || continue
          basename "$n"
          return 0
        done
        return 1
      }

      carrier() { [ "$(cat "/sys/class/net/$1/carrier" 2>/dev/null)" = 1 ]; }
      admin_up() { ip -o link show dev "$1" | grep -q '[<,]UP[,>]'; }
      wait_carrier() {
        for _ in $(seq 1 "$2"); do carrier "$1" && return 0; sleep 1; done
        return 1
      }

      down_for=0
      while true; do
        if ! dev=$(pick); then sleep 60; continue; fi
        # Leave interfaces someone took down on purpose alone.
        if ! admin_up "$dev" || carrier "$dev"; then
          down_for=0; sleep "$interval"; continue
        fi
        down_for=$((down_for + interval))
        if [ "$down_for" -lt "$grace" ]; then sleep "$interval"; continue; fi

        echo "$dev: no carrier for ''${down_for}s, bouncing the link"
        ip link set dev "$dev" down; sleep 2; ip link set dev "$dev" up
        if wait_carrier "$dev" 20; then
          echo "$dev: carrier back after link bounce"
        else
          pci=$(basename "$(readlink -f "/sys/class/net/$dev/device")")
          echo "$dev: still no carrier, rebinding $pci to r8169"
          echo "$pci" > /sys/bus/pci/drivers/r8169/unbind
          sleep 2
          echo "$pci" > /sys/bus/pci/drivers/r8169/bind
          sleep 5
          if dev=$(pick) && wait_carrier "$dev" 30; then
            echo "$dev: carrier back after rebind"
          else
            echo "no carrier after rebind; cable or switch port? retrying in ''${backoff}s"
            sleep "$backoff"
          fi
        fi
        down_for=0
      done
    '';
  };
in {
  # NetworkManager already holds the lease, gateway and DNS on these boxes;
  # the scripted dhcpcd from t640.nix's useDHCP default was a second DHCP
  # client on the same port, doubling every route. useDHCP = false alone left
  # dhcpcd.service in place, so disable it outright. Switching a live box over:
  # make sure `nmcli device show` reports "connected" first, since NM can drop
  # the link during activation and dhcpcd may be all that's left.
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;

  systemd.services.wired-link-watchdog = {
    description = "Recover the onboard NIC after a stuck link";
    wantedBy = ["multi-user.target"];
    after = ["NetworkManager.service"];
    serviceConfig = {
      ExecStart = lib.getExe watchdog;
      Restart = "always";
      RestartSec = 10;
    };
  };
}
