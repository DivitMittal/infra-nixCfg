{inputs, ...}: {
  imports = [inputs.actions-nix.flakeModules.default];

  _module.args = let
    # atticd on T1 (hosts/nixos/T1/attic.nix), over the tailnet
    atticEndpoint = "http://t1:8080";
    atticCache = "infra";
  in rec {
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
      ## Self-hosted attic cache on T1, reached over the tailnet. Stays off
      ## until the ATTIC_TOKEN and TS_OAUTH_* secrets exist, and never fails
      ## the run (T1 is a home box and may be offline).
      {
        name = "Check for attic credentials";
        id = "attic";
        run = "echo \"enabled=\${{ secrets.ATTIC_TOKEN != '' }}\" >> \"$GITHUB_OUTPUT\"";
      }
      {
        name = "Join the tailnet to reach attic on T1";
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
        name = "Use the attic cache on T1";
        "if" = "steps.attic.outputs.enabled == 'true'";
        env.ATTIC_TOKEN = "\${{ secrets.ATTIC_TOKEN }}";
        # nixpkgs-2605: nixpkgs-unstable no longer evaluates on x86_64-darwin runners
        run = ''
          nix profile install "github:NixOS/nixpkgs/$(jq -r '.nodes["nixpkgs-2605"].locked.rev' flake.lock)#attic-client"
          attic login t1 ${atticEndpoint} "$ATTIC_TOKEN"
          attic use t1:${atticCache}
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
      name = "Push the result to the attic cache on T1";
      "if" = "steps.attic.outputs.enabled == 'true'";
      run = "attic push t1:${atticCache} ./result";
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
