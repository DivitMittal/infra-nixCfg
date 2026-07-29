## L2 — Windows boot slot on the dual-boot machine (user: vanee).
## Ported from playbooks-4-windows' hosts/L2/{main,packages}.yml.
##
## No win.files dotfiles are declared here: home/vanee/ in
## playbooks-4-windows was still empty at migration time (wezterm/tridactyl/
## whkd were disabled there too, and no vanee-specific fastfetch config
## existed despite the Ansible task having no feature gate — a pre-existing
## gap, not something this migration introduced). Add files under ./files/
## and wire them into win.files here once vanee's dotfiles exist.
_: {
  win.user.name = "vanee";

  windot = {
    gitFullName = "vanee";
    # inventory/host_vars/L2/vault.yml held vanee's real git email in the
    # Ansible setup; there is no equivalent source wired up on the Nix side.
    # Deliberately left failing (not a guessed placeholder) until it's
    # supplied — fill in vanee's real address before building this host.
    gitEmail = throw "hosts/win/L2/main.nix: set windot.gitEmail to vanee's real git email before building winConfigurations.l2";
    gitSigningKey = null;

    isLaptop = false;
  };
}
