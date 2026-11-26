{
  config,
  lib,
  ...
}: {
  # Keep L1's alias on the router's reserved address while the terminal
  # configuration input still pins the old DHCP lease.
  config = lib.mkIf (config.hostSpec.hostName == "L1") {
    programs.ssh.settings.T3.HostName = lib.mkForce "192.168.2.8";
  };
}
