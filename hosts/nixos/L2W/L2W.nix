# NixOS-WSL inside L2's Windows install. Besides being a Linux shell there, it
# is where nix-win evaluates winConfigurations.l2: nix-win.ps1 runs
# `wsl.exe -d NixOS -u <Windows username>`, so the default user is vanee.
_: {
  networking.nameservers = [];

  # The distro was imported from the NixOS-WSL 26.05 tarball.
  system.stateVersion = "26.05";

  wsl = {
    enable = true;
    defaultUser = "vanee";
    useWindowsDriver = true;

    interop = {
      includePath = true;
      register = true; # keeps .exe launching working alongside binfmt
    };
    startMenuLaunchers = false;

    wslConf = {
      automount = {
        enabled = true;
        root = "/mnt";
      };
      boot.systemd = true;
      user.default = "vanee";
    };
  };
}
