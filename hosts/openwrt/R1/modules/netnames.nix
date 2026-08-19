_: {
  ## Stable NIC naming by MAC.
  #
  # R1 carries an onboard RTL8105e (PCI) plus two USB RTL8153 gigabit adapters.
  # Adding/removing a USB adapter reshuffles the USB eth* numbering, which can
  # move the LAN onto the wrong adapter and strand the management path. Pinning
  # the two USB MACs removes that failure mode: the S1 uplink is always `lan0`
  # and the WAN uplink is always `wan0`. The onboard PCI NIC is deterministically
  # `eth0` and initializes before overlay hotplug scripts, so it remains `eth0`.
  #
  # The hook fires on the netdev `add` event — before netifd configures a
  # physical device — so the rename target is administratively down and the
  # rename is safe. Virtual devices are excluded: br-lan inherits lan0's MAC
  # and must not be mistaken for the physical USB NIC. netifd then binds its
  # config (br-lan and wan) to these stable names.
  uci.files = [
    {
      path = "/etc/hotplug.d/net/10-pin-nics";
      executable = true;
      content = ''
        #!/bin/sh
        [ "$ACTION" = add ] || exit 0
        [ -n "$DEVICENAME" ] || exit 0
        [ -e "/sys/class/net/$DEVICENAME" ] || exit 0
        # Bridges, VLANs, tunnels, and other virtual netdevs have no backing
        # device. br-lan inherits lan0's MAC, so filtering here is essential.
        [ -e "/sys/class/net/$DEVICENAME/device" ] || exit 0

        mac=$(cat "/sys/class/net/$DEVICENAME/address" 2>/dev/null)
        case "$mac" in
          00:e0:4c:4d:2e:78) want=lan0 ;;  # USB RTL8153 → S1 port1 (flat LAN)
          00:e0:4c:55:34:28) want=wan0 ;;  # USB RTL8153 → R0 (WAN)
          *) exit 0 ;;
        esac
        [ "$DEVICENAME" = "$want" ] && exit 0

        # If the wanted name is currently held by another NIC, park that NIC out
        # of the way; its own add event renames it correctly in turn.
        if [ -e "/sys/class/net/$want" ]; then
          ip link set "$want" down 2>/dev/null
          ip link set "$want" name "park-$DEVICENAME" 2>/dev/null
        fi
        ip link set "$DEVICENAME" down 2>/dev/null
        ip link set "$DEVICENAME" name "$want" 2>/dev/null
      '';
    }
  ];
}
