## L1 — Windows boot slot on the triple-boot MacBook (user: div).
## Ported from playbooks-4-windows' hosts/L1/{main,packages}.yml.
{inputs, ...}: {
  win.user.name = "div";

  win.scoop.packages = {
    # CPU power management — MacBook-specific
    throttlestop.bucket = "extras";
  };

  windot = {
    # Reuses the identity already pulled from OS-nixCfg-secrets for every
    # other host (see common/all/hostSpec.nix) — no new secret needed.
    gitFullName = inputs.OS-nixCfg-secrets.user.userFullName;
    gitEmail = inputs.OS-nixCfg-secrets.user.email.dev;
    # The Ansible version read this from inventory/host_vars/L1/vault.yml
    # (vault_git_signing_key). No equivalent exists yet on the Nix side —
    # add a real key ID here (or wire up a proper source) if commit signing
    # on this Windows account is wanted; left disabled until then.
    gitSigningKey = null;

    isLaptop = true;
  };

  win.files = {
    ".config/wezterm/wezterm.lua".source = ./files/wezterm/wezterm.lua;
    ".config/wezterm/options.lua".source = ./files/wezterm/options.lua;
    ".config/wezterm/binds.lua".source = ./files/wezterm/binds.lua;
    ".config/wezterm/smartSplits.lua".source = ./files/wezterm/smartSplits.lua;
    ".config/wezterm/tabline.lua".source = ./files/wezterm/tabline.lua;

    ".config/fastfetch/config.jsonc".source = ./files/fastfetch/config.jsonc;
    ".config/tridactyl/tridactylrc".source = ./files/tridactyl/tridactylrc;
    ".config/whkdrc".source = ./files/whkdrc;
  };
}
