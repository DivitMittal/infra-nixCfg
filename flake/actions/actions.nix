{inputs, ...}: {
  imports = [inputs.actions-nix.flakeModules.default];

  _module.args = let
    # atticd on T3 (hosts/nixos/T3/attic.nix), at its router reservation.
    # Runners reach the LAN through T1's Tailscale subnet route
    # (hosts/nixos/T1/tailscale.nix), so the tailnet ACL must let tag:ci
    # reach 192.168.2.0/24.
    atticEndpoint = "http://192.168.2.8:8080";
    atticCache = "infra";
    atticRemote = "homelab";
  in rec {
    attic = {
      remote = atticRemote;
      cache = atticCache;
      store = "${atticEndpoint}/${atticCache}";
      endpoint = atticEndpoint;
      # Private (no anonymous pull) cache for Darwin closures; only the
      # manual darwin-offload workflow pushes here, with ATTIC_DARWIN_TOKEN.
      darwinCache = "darwin";
      darwinStore = "${atticEndpoint}/darwin";
    };
    common-on = rec {
      push = {
        branches = ["master"];
        paths-ignore = [
          ## Markup
          "**/*.md"
          "**/*.adoc"
          ## Images
          "**/*.jpeg"
          "**/*.jpg"
          "**/*.png"
          "**/*.svg"
          ## Github Actions
          ".github/**"
          ## git
          ".git*"
          ## assets
          "assets/**"
        ];
      };
      pull_request = push;
      workflow_dispatch = {};
    };
    environment = {
      name = "dev";
    };
    common-permissions = {
      contents = "write";
      id-token = "write";
    };
    common-post-actions = [
      {
        name = "Install Nix";
        uses = "nixbuild/nix-quick-install-action@master";
      }
      {
        name = "Magic Nix Cache(Use Github Actions Cache)";
        uses = "DeterminateSystems/magic-nix-cache-action@main";
      }
      {
        name = "Configure to use personal binary cache @ Cachix";
        uses = "cachix/cachix-action@master";
        "with" = {
          name = "divitmittal";
          authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
          # Pull only: the free tier's 5 GiB can't hold these closures, so
          # builds are pushed to attic instead.
          skipPush = true;
        };
        # An expired token shouldn't take the whole run down with it
        continue-on-error = true;
      }
      {
        name = "SSH-agent with auth for private repos";
        uses = "webfactory/ssh-agent@master";
        "with" = {
          ssh-private-key = "\${{ secrets.SSH_PRIVATE_KEY }}";
        };
      }
      ## Self-hosted attic cache on T3, reached over the tailnet. Stays off
      ## until the ATTIC_TOKEN and TS_OAUTH_* secrets exist, and never fails
      ## the run (T3 is a home box and may be offline).
      {
        name = "Check for attic credentials";
        id = "attic";
        run = "echo \"enabled=\${{ secrets.ATTIC_TOKEN != '' && secrets.TS_OAUTH_CLIENT_ID != '' && secrets.TS_OAUTH_SECRET != '' }}\" >> \"$GITHUB_OUTPUT\"";
      }
      {
        name = "Join the tailnet to reach attic on T3";
        id = "tailnet";
        "if" = "steps.attic.outputs.enabled == 'true'";
        uses = "tailscale/github-action@v3";
        "with" = {
          oauth-client-id = "\${{ secrets.TS_OAUTH_CLIENT_ID }}";
          oauth-secret = "\${{ secrets.TS_OAUTH_SECRET }}";
          tags = "tag:ci";
        };
        continue-on-error = true;
      }
      {
        name = "Use the attic cache on T3";
        id = "attic_setup";
        "if" = "steps.tailnet.outcome == 'success'";
        env.ATTIC_TOKEN = "\${{ secrets.ATTIC_TOKEN }}";
        # nixpkgs-2605: nixpkgs-unstable no longer evaluates on x86_64-darwin runners
        run = ''
          nix profile install "github:NixOS/nixpkgs/$(jq -r '.nodes["nixpkgs-2605"].locked.rev' flake.lock)#attic-client"
          if [ "$RUNNER_OS" = Linux ]; then
            sudo tailscale set --accept-routes=true --accept-dns=false
          fi
          # Keep the JWT out of process arguments and the Nix store.
          install -d -m 700 "$HOME/.config/attic"
          umask 077
          python3 - <<'PYCONFIG'
          import json, os
          from pathlib import Path
          config = Path.home() / ".config/attic/config.toml"
          config.write_text('[servers.${atticRemote}]\nendpoint = "${atticEndpoint}/"\ntoken = ' + json.dumps(os.environ["ATTIC_TOKEN"]) + '\n')
          config.chmod(0o600)
          PYCONFIG
          attic use ${atticRemote}:${atticCache}
        '';
        continue-on-error = true;
      }
      ## term/ai/quant-nixCfg (and branches' path: inputs) point at local
      ## checkouts that don't exist on runners; use their GitHub repos instead.
      {
        name = "Point local-checkout inputs at GitHub";
        run = ''
          overrides=$(jq -r '
            .nodes as $n | $n.root.inputs | to_entries[]
            | select(.value | type == "string") | .key as $k | $n[.value].locked
            | select(.type == "path" or ((.url // "") | startswith("file:")))
            | ((.path // .url) | sub("/+$"; "") | split("/") | last) as $repo
            | if ($repo | test("secrets"))
              then "--override-input \($k) git+ssh://git@github.com/DivitMittal/\($repo).git"
              else "--override-input \($k) github:DivitMittal/\($repo)"
              end' flake.lock | tr '\n' ' ')
          echo "LOCAL_OVERRIDES=$overrides" >> "$GITHUB_ENV"
          echo "overrides: $overrides"
        '';
      }
    ];
    ## Push a build's ./result to attic; pairs with the steps above
    attic-push = {
      name = "Push the result to the attic cache on T3";
      id = "attic_push";
      # infra permits anonymous LAN reads; Darwin closures require privacy review.
      "if" = "runner.os != 'macOS' && steps.attic_setup.outcome == 'success'";
      run = "attic push ${atticRemote}:${atticCache} ./result";
      continue-on-error = true;
    };
    common-actions =
      [
        {
          name = "Checkout repo";
          uses = "actions/checkout@main";
          "with" = {
            fetch-depth = 1;
            persist-credentials = false;
          };
        }
      ]
      ++ common-post-actions;
    common-actions-cred =
      [
        {
          name = "Checkout repo";
          uses = "actions/checkout@main";
          "with" = {
            fetch-depth = 1;
            persist-credentials = true;
          };
        }
      ]
      ++ common-post-actions;
  };

  flake.actions-nix = {
    pre-commit.enable = true;
    defaultValues = {
      jobs = {
        runs-on = "ubuntu-latest";
        timeout-minutes = 90;
      };
    };
  };
}
