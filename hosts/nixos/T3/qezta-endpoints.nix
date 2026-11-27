# Onion and IPFS endpoints for the Qezta websites.
#
# Clearnet stays on Vercel (DNS in Qezta/infra). This host does not scrape it.
# qezta.com is the Nix build of Qezta/site (adapter-static). divit.qezta.com
# uses a reverse proxy over Tor for chat and a chat-free static build on IPFS.
# The declarative endpoints are:
#
#   * hidden services generated from `proxies`
#   * IPFS pins of the store paths in `ipfsRoots`
#   * the SSH onion, which is the existing k3s Service in ssh-portfolio.nix
#
# No extra Deployment. Tor and Kubo are host daemons: hidden-service keys and
# the IPFS repo must survive on the host, and Kubo wants host networking.
# A pod would only add hostNetwork plus a hostPath.
#
# Onion hostnames are generated on first start (not known at evaluation) and
# recorded in /var/lib/qezta-endpoints/endpoints.txt.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  qeztaSite = import ./_qezta-site.nix {
    inherit pkgs;
    src = inputs.qezta-site;
  };

  divitMirror = import ./_divit-ipfs.nix {
    inherit pkgs;
    src = inputs.divit-ipfs;
  };

  ipfsGatewayPort = 8082;
  ipfsOnionPort = 8093;
  ipfsDataDir = config.services.kubo.dataDir;
  publishState = "/var/lib/qezta-ipfs-publish";
  endpointState = "/var/lib/qezta-endpoints";
  ipfs = "${pkgs.kubo}/bin/ipfs";

  # One table. nginx listeners, Tor maps, and the IPFS record are all
  # generated from this. Add a site here; do not edit the shell scripts.
  proxies = {
    # Same store path as the qezta IPNS pin. Relative /_app paths, index at /.
    qezta-www = {
      port = 8091;
      root = qeztaSite;
    };
    # Keep the live chatbot available over Tor through the Vercel backend.
    divit-www = {
      port = 8092;
      host = "divit.qezta.com";
      redirectHosts = ["divit.qezta.com" "www.divit.qezta.com"];
    };
  };

  # Store paths pinned under their own IPNS keys. A rebuild republishes
  # because the path is a restartTrigger. Do not scrape Vercel into here.
  # `endpoints` is the host record. Each site has a separate IPNS key.
  ipfsRoots = {
    divit = divitMirror;
    endpoints = endpointRecord;
    qezta = qeztaSite;
  };

  shellArg = lib.escapeShellArg;

  publishInvocations = lib.concatStringsSep "\n" (lib.mapAttrsToList (
      name: root: "ensure_key ${shellArg name} || failed=1\npublish_root ${shellArg name} ${shellArg root} || failed=1"
    )
    ipfsRoots);

  # Nix double-quoted \n is a newline. printf needs the two characters \n.
  ipnsLines = lib.concatMapStringsSep "\n" (
    name: "printf '%s %s\\n' ${shellArg name} \"\$(key_id ${shellArg name})\""
  ) (lib.attrNames ipfsRoots);

  endpointRecord = pkgs.runCommand "qezta-endpoint-record" {} ''
    mkdir -p $out
    cat > $out/endpoints.json <<'EOF'
    ${builtins.toJSON {
      proxies = lib.mapAttrs (_: site:
        if site ? host
        then {
          inherit (site) host;
          upstream = "https://${site.host}/";
          inherit (site) redirectHosts;
        }
        else {
          kind = "nix-store";
        })
      proxies;
      ssh = {
        service = "qezta-ssh/ssh-portfolio";
        nodePort = 30022;
        clearnet = "ssh divit@qezta.com";
      };
      note = "Onion hostnames and IPNS ids are host state, not in this pin. ipns.qezta is the company site and ipns.divit is the static portfolio. The divit chatbot is the Vercel upstream, reached through the divit-www onion.";
    }}
    EOF
    cat > $out/index.html <<'EOF'
    <!doctype html>
    <meta charset="utf-8">
    <title>qezta endpoints</title>
    <h1>qezta endpoints</h1>
    <p>This pin is the declarative record, not the site. The company site is under the <code>qezta</code> IPNS key and the static portfolio is under <code>divit</code>.</p>
    <ul>
      <li><a href="https://www.qezta.com/">www.qezta.com</a></li>
      <li><a href="https://divit.qezta.com/">divit.qezta.com</a></li>
    </ul>
    <p>See <code>endpoints.json</code> in this directory.</p>
    EOF
  '';

  listenOn = port: [
    {
      addr = "127.0.0.1";
      inherit port;
      extraParameters = ["default_server"];
    }
  ];

  proxyVHost = name: site: {
    serverName = "${name}.onion.local";
    listen = listenOn site.port;
    locations."/" =
      if site ? root
      then {
        # Store path: types.path accepts a derivation, and the nginx
        # config build depends on it. A runtime directory would not.
        inherit (site) root;
        tryFiles = "$uri $uri/ $uri.html /index.html";
      }
      else {
        proxyPass = "https://${site.host}";
        recommendedProxySettings = false;
        proxyWebsockets = true;
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_ssl_name ${site.host};
          proxy_ssl_verify on;
          proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
          proxy_set_header Host ${site.host};
          proxy_set_header X-Real-IP "";
          proxy_set_header X-Forwarded-For "";
          proxy_set_header X-Forwarded-Host "";
          ${lib.concatMapStrings (host: "proxy_redirect https://${host}/ /;\n") site.redirectHosts}
          proxy_hide_header Strict-Transport-Security;
          proxy_hide_header Content-Security-Policy;
          proxy_hide_header Content-Security-Policy-Report-Only;
          proxy_read_timeout 120s;
          proxy_send_timeout 120s;
        '';
      };
  };

  kuboProxy = ''
    proxy_set_header Host 127.0.0.1:${toString ipfsGatewayPort};
    proxy_set_header X-Forwarded-For "";
  '';

  publishScript = pkgs.writeShellScript "qezta-ipfs-publish" ''
    set -euo pipefail
    export IPFS_PATH=${ipfsDataDir}
    mkdir -p ${publishState}

    for _ in $(seq 1 30); do
      if ${ipfs} id >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    ${ipfs} id >/dev/null

    ensure_key() {
      local name="$1"
      if ! ${ipfs} key list | grep -qx "$name"; then
        ${ipfs} key gen --type=ed25519 "$name" >/dev/null
      fi
    }

    key_id() {
      local name="$1"
      ${ipfs} key list -l | awk -v n="$name" '$1 == n { print $2 } $2 == n { print $1 }'
    }

    publish_root() {
      local name="$1" root="$2" cid prev="" prev_file
      prev_file=${publishState}/$name.cid
      if [[ -f $prev_file ]]; then
        prev=$(<"$prev_file")
      fi
      cid=$(${ipfs} add -r -Q --pin=false --cid-version=1 "$root") || return 1
      ${ipfs} pin add "$cid" || return 1
      if ${ipfs} name publish --key="$name" --lifetime=168h "/ipfs/$cid"; then
        if [[ -n $prev && $prev != "$cid" ]]; then
          ${ipfs} pin rm "$prev" || true
        fi
        printf '%s\n' "$cid" >"$prev_file"
        echo "published $name /ipfs/$cid"
      else
        if [[ $cid != "$prev" ]]; then
          ${ipfs} pin rm "$cid" || true
        fi
        echo "IPNS publish failed for $name" >&2
        return 1
      fi
    }

    failed=0
    ${publishInvocations}

    {
      printf 'peer %s\n' "$(${ipfs} id -f '<id>')"
      ${ipnsLines}
    } >${publishState}/ipns.txt
    chmod 0644 ${publishState}/ipns.txt
    exit "$failed"
  '';

  collectScript = pkgs.writeShellScript "qezta-endpoints" ''
    set -euo pipefail
    install -d -m 0755 ${endpointState}
    out=${endpointState}/endpoints.txt
    html=${endpointState}/ipfs-index.html
    tmp=$(mktemp)

    {
      echo "# Generated on T3 from Tor state and the IPFS repo. Do not edit."
      if [[ -d /var/lib/tor/onion ]]; then
        for dir in /var/lib/tor/onion/*; do
          [[ -s $dir/hostname ]] || continue
          printf 'onion.%s %s\n' "$(basename "$dir")" "$(tr -d '[:space:]' <"$dir/hostname")"
        done
      fi
      if [[ -f ${publishState}/ipns.txt ]]; then
        while read -r name id; do
          [[ -n $name && -n $id ]] || continue
          printf 'ipns.%s %s\n' "$name" "$id"
        done <${publishState}/ipns.txt
      fi
    } >"$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$out"

    cat >"$html" <<'EOF'
    <!doctype html>
    <meta charset="utf-8">
    <title>qezta IPFS</title>
    <h1>qezta IPFS</h1>
    <p>Local pins only. This gateway does not fetch arbitrary content.</p>
    EOF
    while read -r key value; do
      [[ $key == ipns.* && -n $value ]] || continue
      printf '<p><a href="/ipns/%s/">%s</a></p>\n' "$value" "$key" >>"$html"
    done <"$out"
    chmod 0644 "$html"
    cat "$out"
  '';
in {
  services.nginx = {
    enable = true;
    defaultListenAddresses = [];
    proxyResolveWhileRunning = true;
    recommendedProxySettings = false;
    resolver.addresses = ["1.1.1.1" "1.0.0.1"];
    resolver.valid = "30s";
    virtualHosts =
      lib.mapAttrs proxyVHost proxies
      // {
        qezta-ipfs = {
          serverName = "qezta-ipfs.onion.local";
          listen = [
            {
              addr = "127.0.0.1";
              port = ipfsOnionPort;
              extraParameters = ["default_server"];
            }
          ];
          locations."/ipfs/" = {
            proxyPass = "http://127.0.0.1:${toString ipfsGatewayPort}";
            recommendedProxySettings = false;
            extraConfig = kuboProxy;
          };
          locations."/ipns/" = {
            proxyPass = "http://127.0.0.1:${toString ipfsGatewayPort}";
            recommendedProxySettings = false;
            extraConfig = kuboProxy;
          };
          # types.path must exist at evaluation; this directory is host state.
          locations."/" = {
            extraConfig = ''
              root ${endpointState};
              try_files /ipfs-index.html =404;
            '';
          };
        };
      };
  };

  services.tor = {
    enable = true;
    relay.onionServices =
      lib.mapAttrs (_: site: {
        version = 3;
        map = [
          {
            port = 80;
            target = {
              addr = "127.0.0.1";
              inherit (site) port;
            };
          }
        ];
      })
      proxies
      // {
        qezta-ipfs = {
          version = 3;
          map = [
            {
              port = 80;
              target = {
                addr = "127.0.0.1";
                port = ipfsOnionPort;
              };
            }
          ];
        };
      };
  };

  # T3 has about 3.3 GiB usable. DHT client only: not a public gateway, not
  # a relay for other people. Attic already owns host port 8080.
  services.kubo = {
    enable = true;
    enableGC = true;
    localDiscovery = false;
    settings = {
      Addresses.Gateway = "/ip4/127.0.0.1/tcp/${toString ipfsGatewayPort}";
      Addresses.API = "/unix/run/ipfs.sock";
      Addresses.Swarm = [
        "/ip4/0.0.0.0/tcp/4001"
        "/ip4/0.0.0.0/udp/4001/quic-v1"
      ];
      Datastore.StorageMax = "2GB";
      Discovery.MDNS.Enabled = false;
      Gateway.NoFetch = true;
      Routing.Type = "dhtclient";
      Swarm.RelayService.Enabled = false;
      Swarm.RelayClient.Enabled = true;
      Swarm.ConnMgr = {
        LowWater = 20;
        HighWater = 40;
        GracePeriod = "30s";
      };
    };
  };

  systemd.services.ipfs.serviceConfig = {
    MemoryHigh = "512M";
    MemoryMax = "768M";
  };

  systemd.services.tor.after = ["nginx.service"];
  systemd.services.tor.wants = ["nginx.service"];

  systemd.services.qezta-ipfs-publish = {
    description = "Pin and IPNS-publish the Qezta sites and endpoint record";
    wantedBy = ["multi-user.target"];
    after = ["ipfs.service" "network-online.target"];
    wants = ["ipfs.service" "network-online.target"];
    restartTriggers = lib.attrValues ipfsRoots;
    path = [pkgs.kubo pkgs.gawk pkgs.gnugrep pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      User = "ipfs";
      Group = "ipfs";
      StateDirectory = "qezta-ipfs-publish";
      TimeoutStartSec = "40min";
      PrivateTmp = true;
      ExecStartPost = "+${collectScript}";
    };
    script = ''
      exec ${publishScript}
    '';
  };

  systemd.services.qezta-endpoints = {
    description = "Record qezta onion hostnames and IPNS names";
    after = ["tor.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.gawk pkgs.gnugrep pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      TimeoutStartSec = "2min";
    };
    script = ''
      for _ in $(seq 1 30); do
        if [[ -s /var/lib/tor/onion/qezta-www/hostname ]]; then
          break
        fi
        sleep 1
      done
      ${collectScript}
    '';
  };

  systemd.timers.qezta-ipfs-publish = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.timers.qezta-endpoints = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };

  # Only the swarm has public ingress. HTTP listeners stay on loopback.
  networking.firewall.allowedTCPPorts = [4001];
  networking.firewall.allowedUDPPorts = [4001];

  topology.self.services.qezta-endpoints = {
    name = "Qezta onion and IPFS";
    info = "Tor proxies to Vercel; IPFS pins Nix paths only. Addresses in ${endpointState}/endpoints.txt";
  };
}
