_: {
  uci = {
    packageManager = "apk";

    # Keep the deployer's active key declarative so network/dropbear reloads
    # cannot leave R1 reachable only by password.
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJpWflssiRPxxQSj4vpS4vIYR5qpZ1biVTscWTkDtstB 64.69.76.69.74.m@gmail.com"
    ];

    packages = [
      "btop"
      "iperf3"
      "libustream-mbedtls20201210"
      "speedtest-go"
    ];

    settings = {
      system.system = [
        {
          _type = "system";
          hostname = "R1";
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
