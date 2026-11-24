# Imported by T1 and T3: a `wake-t2` command that sends a Wake-on-LAN magic
# packet to T2's onboard NIC. T2's BIOS "S5 Wake on LAN" has been switched to
# Enable (docs/hp-t640-bios.md); this is the sending side, over the home LAN
# broadcast address, from either of the other two t640s.
{
  pkgs,
  inputs,
  ...
}: let
  t2Mac = inputs.infra-nixCfg-secrets.homelab.macs.T2;
in {
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "wake-t2";
      runtimeInputs = [pkgs.wakeonlan];
      text = ''
        exec wakeonlan -i 192.168.2.255 ${t2Mac}
      '';
    })
  ];
}
