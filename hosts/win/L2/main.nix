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
    # vanee's address lived in the retired Ansible vault; until it's added
    # here, git on L2 runs without a user.email (commits will prompt for it).
    gitEmail = null;
    gitSigningKey = null;

    isLaptop = false;
  };
}
