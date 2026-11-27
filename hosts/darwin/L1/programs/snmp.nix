{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.net-snmp
    (pkgs.writeShellApplication {
      name = "r0-snmp-status";
      runtimeInputs = [pkgs.net-snmp pkgs.coreutils];
      text = ''
        # SNMPCONFPATH keeps credentials out of command arguments and the store.
        confdir="''${R0_SNMP_CONFIG_DIR:-$HOME/.config/r0-snmp}"
        if [ ! -r "$confdir/snmp.conf" ]; then
          echo "Missing $confdir/snmp.conf; see docs/homelab-snmp.md" >&2
          exit 1
        fi
        # Pin GNU stat: macOS /usr/bin/stat uses a different interface.
        mode="$(${pkgs.coreutils}/bin/stat -Lc '%a' -- "$confdir/snmp.conf")"
        if (( (8#$mode & 077) != 0 )); then
          echo "Refusing snmp.conf with group/other permissions; set mode 0600" >&2
          exit 1
        fi
        export SNMPCONFPATH="$confdir"
        exec snmpget -On -t 2 -r 1 192.168.1.1 \
          .1.3.6.1.2.1.1.1.0 .1.3.6.1.2.1.1.2.0 .1.3.6.1.2.1.1.3.0
      '';
    })
  ];
}
