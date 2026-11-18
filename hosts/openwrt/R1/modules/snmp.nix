_: {
  uci = {
    packages = ["snmpd"];

    # Community strings are generated on-device (see reconcile.d hook below)
    # instead of being declared here, so they never land in git.
    settings.snmpd = {
      agent = {
        _type = "agent";
        agentaddress = "161";
      };

      all = {
        _type = "view";
        viewname = "all";
        type = "included";
        oid = ".1";
      };

      ro_group = {
        _type = "group";
        secname = "ro";
        version = "v2c";
      };

      rw_group = {
        _type = "group";
        secname = "rw";
        version = "v2c";
      };

      ro_access = {
        _type = "access";
        group = "ro_group";
        context = "none";
        version = "v2c";
        level = "none";
        prefix = "exact";
        read = "all";
        write = "none";
        notify = "none";
      };

      rw_access = {
        _type = "access";
        group = "rw_group";
        context = "none";
        version = "v2c";
        level = "none";
        prefix = "exact";
        read = "all";
        write = "all";
        notify = "none";
      };
    };

    files = [
      {
        path = "/etc/nuci/reconcile.d/60-snmp";
        executable = true;
        content = ''
          #!/bin/sh
          set -eu

          gen_community() {
            umask 077
            tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 > "$1"
            echo >> "$1"
          }

          ro_file=/etc/nuci/snmp-ro-community
          [ -s "$ro_file" ] || {
            gen_community "$ro_file"
            echo "Generated SNMP RO community string; retrieve it from $ro_file"
          }
          rw_file=/etc/nuci/snmp-rw-community
          [ -s "$rw_file" ] || {
            gen_community "$rw_file"
            echo "Generated SNMP RW community string; retrieve it from $rw_file"
          }
          ro_community="$(head -n1 "$ro_file")"
          rw_community="$(head -n1 "$rw_file")"

          uci set snmpd.ro_com2sec="com2sec"
          uci set snmpd.ro_com2sec.secname="ro"
          uci set snmpd.ro_com2sec.community="$ro_community"

          uci set snmpd.rw_com2sec="com2sec"
          uci set snmpd.rw_com2sec.secname="rw"
          uci set snmpd.rw_com2sec.community="$rw_community"
          uci commit snmpd

          service=/etc/init.d/snmpd
          [ -x "$service" ] || {
            echo "snmpd init service is unavailable" >&2
            exit 1
          }
          "$service" enable
          "$service" restart
        '';
      }
    ];
  };
}
