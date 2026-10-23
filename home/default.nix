{
  mkCfg,
  inputs,
  ...
}: {
  imports = [inputs.home-manager.flakeModules.home-manager];

  flake.homeConfigurations = let
    class = "home";
    fullModules =
      [
        (inputs.import-tree ./tty)
      ]
      ++ [./gui/setup.nix]
      ++ [(inputs.import-tree ./dev)]
      ++ [(inputs.import-tree ./comms)]
      ++ [(inputs.import-tree ./tools)]
      ++ [(inputs.import-tree ./web)]
      ++ [(inputs.import-tree ./media)];
    ttyDevModules = [
      (inputs.import-tree ./tty)
      (inputs.import-tree ./dev)
    ];
    headlessModules = [
      {fonts.fontconfig.enable = false;}
      ./tty/alt.nix
      ./tty/atuin.nix
      ./tty/btop.nix
      ./tty/help.nix
      ./tty/viewers.nix
      ./tty/editors/editorconfig.nix
      ./tty/editors/misc.nix
      ./tty/editors/vim.nix
      (inputs.import-tree ./tty/find)
      ./tty/network/misc.nix
      (inputs.import-tree ./tty/pagers)
      (inputs.import-tree ./tty/shells)
      (inputs.import-tree ./tty/vcs)
      (inputs.import-tree ./dev)
    ];
  in {
    # ── darwin ──────────────────────────────────────────────────────────────
    L1 = mkCfg {
      hostName = "L1";
      system = "x86_64-darwin";
      inherit class;
      additionalModules = fullModules;
    };

    ASL1 = mkCfg {
      hostName = "ASL1";
      system = "aarch64-darwin";
      inherit class;
      additionalModules = fullModules;
    };

    # ── nixos ───────────────────────────────────────────────────────────────
    L2 = mkCfg {
      hostName = "L2";
      system = "x86_64-linux";
      inherit class;
      additionalModules = fullModules;
    };

    T2 = mkCfg {
      hostName = "T2";
      system = "x86_64-linux";
      inherit class;
      additionalModules = fullModules;
    };

    ASL1N = mkCfg {
      hostName = "ASL1N";
      system = "aarch64-linux";
      inherit class;
      additionalModules = fullModules;
    };

    WSL = mkCfg {
      hostName = "WSL";
      system = "x86_64-linux";
      inherit class;
      additionalModules = ttyDevModules;
    };

    colima = mkCfg {
      hostName = "colima";
      system = "x86_64-linux";
      inherit class;
      additionalModules = ttyDevModules;
    };

    colima-arm = mkCfg {
      hostName = "colima";
      system = "aarch64-linux";
      inherit class;
      additionalModules = ttyDevModules;
    };

    VPS0 = mkCfg {
      hostName = "VPS0";
      system = "aarch64-linux";
      inherit class;
      additionalModules = headlessModules;
    };

    VPS1 = mkCfg {
      hostName = "VPS1";
      system = "x86_64-linux";
      inherit class;
      additionalModules = headlessModules;
    };

    # ── droid ────────────────────────────────────────────────────────────────
    M1 = mkCfg {
      hostName = "M1";
      system = "aarch64-linux";
      inherit class;
      additionalModules = [(inputs.import-tree ./tty)];
    };
  };
}
