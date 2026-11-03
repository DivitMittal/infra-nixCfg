## Human-facing chat TUIs. Agent-facing CLIs (matrix-commander-rs, ii) live in
## ai-nixCfg's config/home/comms.nix.
{
  lib,
  pkgs,
  hostPlatform,
  inputs,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    telegram-tui = inputs.tgt.packages.${hostPlatform.system}.default;
    ## npm-only (Node >= 22), not in nixpkgs. Doubles as an agent tool: its
    ## non-TUI subcommands accept `-o json`.
    instagram-cli = lib.custom.mkPnpmDlxBin "instagram-cli" "@i7m/instagram-cli@latest";
    inherit
      (pkgs)
      # gomuks # Matrix TUI; replaced by iamb
      nchat # WhatsApp + Telegram TUI (Signal needs a HAS_SIGNAL build, not in nixpkgs)
      ;
  };

  ## Matrix TUI. Login is interactive (password/SSO); the session is stored
  ## under ~/.local/share/iamb, so only the profile's user_id belongs in config.
  programs.iamb.enable = true;

  programs.discordo = {
    enable = true;
    settings = {
      keybinds.guilds_tree = {
        up = "Up";
        down = "Down";
      };
      keybinds.messages_list = {
        select_up = "Up";
        select_down = "Down";
        scroll_up = "Ctrl+Up";
        scroll_down = "Ctrl+Down";
      };
    };
  };
}
