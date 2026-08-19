_: {
  uci = {
    packages = [
      "coreutils-base64"
      "ksmbd-server"
      "wsdd2"
    ];

    settings.ksmbd = {
      global = {
        _type = "globals";
        workgroup = "WORKGROUP";
        description = "R1 NAS";
        interface = "lan tailscale";
      };

      share = [
        {
          _type = "share";
          name = "WD-NAS";
          path = "/srv/nas";
          comment = "WD My Passport";
          users = "nas";
          browseable = "yes";
          read_only = "no";
          guest_ok = "no";
          create_mask = "0664";
          dir_mask = "0775";
        }
      ];
    };

    files = [
      {
        path = "/etc/nuci/reconcile.d/20-nas";
        executable = true;
        content = ''
          #!/bin/sh
          set -eu

          if ! grep -q '^nas:' /etc/ksmbd/ksmbdpwd.db 2>/dev/null; then
            umask 077
            password="$(dd if=/dev/urandom bs=18 count=1 2>/dev/null | base64)"
            ksmbd.adduser -a nas -p "$password"
            printf '%s\n' "$password" > /etc/nuci/nas-initial-password
            echo "Created SMB user 'nas'; retrieve its password from /etc/nuci/nas-initial-password"
          fi

          for service in ksmbd wsdd2; do
            init="/etc/init.d/$service"
            [ -x "$init" ] || {
              echo "$service init service is unavailable" >&2
              exit 1
            }
            "$init" enable
            "$init" restart
          done
        '';
      }
    ];
  };
}
