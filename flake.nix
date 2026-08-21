{
  description = "infra-nixCfg's flake";

  outputs = {nixpkgs, ...} @ inputs: let
    inherit (inputs.flake-parts.lib) mkFlake;
    # Per-system nixpkgs source — pick the 26.05-darwin branch on x86_64-darwin
    # (the only system NixOS 26.11 dropped), else fall back to nixpkgs-unstable.
    specialArgs.lib = nixpkgs.lib.extend (final: _: {
      custom = import ./lib/custom.nix {lib = final;};
    });
  in
    mkFlake {inherit inputs specialArgs;} ({
      inputs,
      lib,
      self,
      ...
    }: {
      systems = import inputs.systems;
      perSystem = {system, ...}: {
        # Note: We use non-memoized pkgs here instead of the memoized version
        # (inputs.nixpkgs.legacyPackages.${system}) because we need to apply
        # custom config options and overlays. While this means pkgs is re-evaluated
        # for each system, it's necessary to get our custom configuration.
        # The memoized version would not include our overlays and config settings.
        #
        # Trade-off: Slightly longer evaluation time vs. ability to customize pkgs
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config = let
            inherit (lib) mkDefault;
          in {
            allowUnfree = mkDefault true;
            allowBroken = mkDefault false;
            allowUnsupportedSystem = mkDefault false;
            checkMeta = mkDefault false;
            # warnUndeclaredOptions is intentionally left at its nixpkgs default
            # (false). Turning it on produces permanent false-positive noise:
            # `permittedInsecurePackages` is read by check-meta.nix but never
            # declared in nixpkgs' schema, and `_undeclared` itself gets
            # re-emitted by the freeformType merge on every evaluation where
            # any undeclared option exists.
            #
            # libolm (used by gomuks Matrix TUI client) is deprecated upstream
            permittedInsecurePackages = mkDefault ["olm-3.2.16"];
          };
          overlays = lib.attrsets.attrValues {
            inherit (self.outputs.overlays) default;
          };
        };
      };
      imports = [
        (inputs.import-tree ./flake)
        ./home
        ./hosts
        ./modules
        ./overlays
        ./templates
      ];
    });

  inputs = {
    ### nixpkgs (from most unstable to stable)
    #nixpkgs-staging.url = "github:nixos/nixpkgs/staging";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    "nixpkgs-2605".url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-2505.url = "github:nixos/nixpkgs/nixos-25.05";
    #nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    ## Nix User Repository (NUR)
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ## nixpkgs indexed
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## import-tree
    import-tree.url = "github:vic/import-tree";

    ## flake helpers
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    ## flake-parts
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    actions-nix = {
      url = "github:nialov/actions.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        git-hooks.follows = "git-hooks";
      };
    };

    ## Secrets
    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        darwin.follows = "nix-darwin";
        systems.follows = "systems";
      };
    };
    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs = {
        agenix.follows = "agenix";
        nixpkgs.follows = "nixpkgs";
      };
    };
    infra-nixCfg-secrets = {
      url = "git+ssh://git@github.com/DivitMittal/infra-nixCfg-secrets.git?ref=master";
      #url = "path:/Users/div/Projects/Cfgs/infra-nixCfg-secrets";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        devshell.follows = "devshell";
        agenix.follows = "agenix";
        ragenix.follows = "ragenix";
        actions-nix.follows = "actions-nix";
        git-hooks.follows = "git-hooks";
      };
    };

    ## Editors
    Vim-Cfg = {
      url = "github:DivitMittal/Vim-Cfg";
      #url = "path:/Users/div/Projects/Cfgs/Vim-Cfg";
      flake = false;
    };
    nvchad4nix = {
      url = "github:nix-community/nix4nvchad";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nvchad-starter.follows = "Vim-Cfg";
      };
    };
    Emacs-Cfg = {
      url = "github:DivitMittal/emacs-cfg";
      #url = "path:/Users/div/Projects/Cfgs/Emacs-Cfg";
      flake = false;
    };
    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    ## Terminal Emulator
    term-nixCfg = {
      #url = "github:DivitMittal/term-nixCfg";
      url = "path:/Users/div/Projects/Cfgs/term-nixCfg";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        systems.follows = "systems";
        devshell.follows = "devshell";
        treefmt-nix.follows = "treefmt-nix";
        git-hooks.follows = "git-hooks";
        actions-nix.follows = "actions-nix";
        import-tree.follows = "import-tree";
      };
    };

    ## Firefox
    firefox-nixCfg = {
      url = "github:DivitMittal/firefox-nixCfg";
      #url = "path:/Users/div/Projects/Cfgs/firefox-nixCfg";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        systems.follows = "systems";
        devshell.follows = "devshell";
        treefmt-nix.follows = "treefmt-nix";
        git-hooks.follows = "git-hooks";
        actions-nix.follows = "actions-nix";
      };
    };

    ## AI
    ai-nixCfg = {
      #url = "github:DivitMittal/ai-nixCfg";
      url = "path:/Users/div/Projects/Cfgs/ai-nixCfg";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        systems.follows = "systems";
        devshell.follows = "devshell";
        treefmt-nix.follows = "treefmt-nix";
        git-hooks.follows = "git-hooks";
        actions-nix.follows = "actions-nix";
      };
    };

    ## Quant / algo trading
    quant-nixCfg = {
      #url = "github:DivitMittal/quant-nixCfg";
      url = "path:/Users/div/Projects/Cfgs/quant-nixCfg";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        systems.follows = "systems";
        devshell.follows = "devshell";
        treefmt-nix.follows = "treefmt-nix";
        git-hooks.follows = "git-hooks";
      };
    };

    ## Spicetify
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spotatui = {
      url = "github:LargeModGames/spotatui";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## TidalCycles
    tidalcycles-nix = {
      url = "github:DivitMittal/tidalcycles-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        systems.follows = "systems";
        devshell.follows = "devshell";
        treefmt-nix.follows = "treefmt-nix";
        git-hooks.follows = "git-hooks";
        actions-nix.follows = "actions-nix";
      };
    };

    ### Infra
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        utils.follows = "flake-utils";
        flake-compat.follows = "flake-compat";
      };
    };
    ## NixOS
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/nixos-wsl/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:nixos/nixos-hardware/master";
    nixos-apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ## Android
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    android-kvm = {
      url = "github:DivitMittal/android-kvm";
      #url = "path:/Users/div/Projects/hid/android-kvm";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
        devshell.follows = "devshell";
        treefmt-nix.follows = "treefmt-nix";
        import-tree.follows = "import-tree";
      };
    };

    lan-mouse = {
      url = "github:feschber/lan-mouse";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    areofyl-fetch = {
      url = "github:areofyl/fetch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## Theming — cyberpunk palette wired via lib/palette.nix
    stylix = {
      url = "github:danth/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nur.follows = "nur";
        systems.follows = "systems";
      };
    };

    ## Home-Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ### macOS
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ## Hammerspoon
    hammerspoon-nix = {
      url = "github:DivitMittal/hammerspoon-nix";
      # url = "path:/Users/div/Projects/Cfgs/hammerspoon-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        systems.follows = "systems";
        devshell.follows = "devshell";
        treefmt-nix.follows = "treefmt-nix";
        git-hooks.follows = "git-hooks";
        actions-nix.follows = "actions-nix";
      };
    };
    ## Declarative homebrew setup
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew"; # Bootstrapping homebrew
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    macos-fuse-t-cask = {
      url = "github:macos-fuse-t/homebrew-cask";
      flake = false;
    };

    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      #url = "github:DivitMittal/brew-nix/fix/7zip-26-dangerous-links";
      #url = "path:/Users/div/Developer/Forks/brew-nix";
      inputs = {
        brew-api.follows = "brew-api";
        nix-darwin.follows = "nix-darwin";
        nixpkgs.follows = "nixpkgs";
      };
    };
    brew-api = {
      url = "github:batteredbunny/brew-api";
      flake = false;
    };
    ## Trampolines for GUI .app bundles
    mac-app-util = {
      url = "github:mcflis/mac-app-util/fix/missing-icons";
      #url = "github:hraban/mac-app-util";
      inputs = {
        #nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        systems.follows = "systems";
      };
    };

    ## Keyboard
    kanata-tray = {
      url = "github:rszyma/kanata-tray";
      #url = "github:DivitMittal/kanata-tray/fix/nix-hostplatform-system";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    TLTR = {
      url = "github:DivitMittal/TLTR";
      flake = false;
    };

    ## Topology
    nix-topology = {
      url = "github:oddlama/nix-topology";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };

    ## Misc.
    yazi = {
      url = "github:sxyazi/yazi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yazi-plugins = {
      url = "github:yazi-rs/plugins";
      flake = false;
    };
    leetcode-tui = {
      url = "github:akarsh1995/leetcode-tui";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    tgt = {
      ## Don't follow nixpkgs - tgt uses apple-sdk_12 which was removed in newer nixpkgs
      url = "github:FedericoBruzzone/tgt";
    };
    PKMS = {
      url = "github:DivitMittal/PKMS";
      flake = false;
    };
  };

  ## These caches only contain binaries for packages used by this config,
  ## so they're scoped to the flake rather than polluting global nix settings.
  nixConfig = {
    extra-substituters = [
      "https://yazi.cachix.org"
      "https://wezterm.cachix.org"
      "https://cache.numtide.com"
      #"https://cache.lix.systems"
    ];
    extra-trusted-public-keys = [
      "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
      "wezterm.cachix.org-1:kAbhjYUC9qvblTE+s7S+kl5XM1zVa4skO+E/1IDWdH0="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      #"cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
    ];
  };
}
