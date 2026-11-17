_: {
  uci = {
    packageManager = "apk";

    # Same deployer key as R1 (hosts/openwrt/R1/modules/base.nix) — one
    # person operates both routers.
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJpWflssiRPxxQSj4vpS4vIYR5qpZ1biVTscWTkDtstB"
    ];

    settings = {
      system.system = [
        {
          _type = "system";
          hostname = "T640";
        }
      ];

      dropbear.main = {
        _type = "dropbear";
        enable = "1";
        PasswordAuth = "on";
        RootPasswordAuth = "on";
        Port = "22";
      };
    };
  };
}
