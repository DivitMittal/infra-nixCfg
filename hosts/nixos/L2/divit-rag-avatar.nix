{
  inputs,
  lib,
  pkgs,
  ...
}: let
  appUser = "divit-avatar";
  appGroup = appUser;
  appPort = 3000;
  appRoot = "/srv/divit/current";
  appEnvFile = "/run/agenix/divit-avatar.env";
  dbName = "divit_avatar";
in {
  imports = [inputs.agenix.nixosModules.default];

  networking.firewall.allowedTCPPorts = [80 443];

  services.caddy = {
    enable = true;
    virtualHosts."divit.qezta.com".extraConfig = ''
      reverse_proxy 127.0.0.1:${toString appPort}
    '';
  };

  users.groups.${appGroup} = {};
  users.users.${appUser} = {
    isSystemUser = true;
    group = appGroup;
    home = "/var/lib/${appUser}";
    createHome = true;
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    extensions = ps: [ps.pgvector];
    ensureDatabases = [dbName];
    ensureUsers = [
      {
        name = appUser;
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.divit-avatar = {
    description = "Divit self-hosted portfolio and RAG avatar";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "postgresql.service"];
    wants = ["network-online.target" "postgresql.service"];
    environment = {
      HOST = "127.0.0.1";
      PORT = toString appPort;
      PUBLIC_BASE_URL = "https://divit.qezta.com";
      RAG_VECTOR_BACKEND = "postgres";
      RAG_TRACE_RAW_CONTENT = "false";
    };
    serviceConfig = {
      User = appUser;
      Group = appGroup;
      WorkingDirectory = appRoot;
      EnvironmentFile = "-${appEnvFile}";
      ExecStart = "${lib.getExe pkgs.nodejs_22} ${appRoot}/build/index.js";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = ["/var/lib/${appUser}"];
    };
  };

  systemd.services.divit-avatar-migrate = {
    description = "Run Divit RAG database migrations";
    after = ["postgresql.service"];
    wants = ["postgresql.service"];
    serviceConfig = {
      Type = "oneshot";
      User = appUser;
      Group = appGroup;
      WorkingDirectory = appRoot;
      EnvironmentFile = "-${appEnvFile}";
      ExecStart = "${pkgs.bash}/bin/bash -lc '${pkgs.postgresql_16}/bin/psql \"$DATABASE_URL\" -f ${appRoot}/migrations/001_rag_pgvector.sql'";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.services.divit-avatar-health = {
    description = "Check Divit avatar health endpoint";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.curl}/bin/curl --fail --silent --show-error http://127.0.0.1:${toString appPort}/health";
    };
  };

  systemd.timers.divit-avatar-health = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Unit = "divit-avatar-health.service";
    };
  };

  services.postgresqlBackup = {
    enable = true;
    databases = [dbName];
    compression = "zstd";
  };
}
