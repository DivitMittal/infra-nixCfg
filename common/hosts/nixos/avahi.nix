# mDNS/DNS-SD: <host>.local names + service discovery (Finder, AirPlay, ESPHome...).
# Trial: delete this file to turn it back off.
{lib, ...}: {
  services.avahi = {
    enable = lib.mkDefault true;
    nssmdns4 = true; # resolve *.local via NSS
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true; # announce <hostname>.local
      workstation = true;
      userServices = true;
    };
  };
}
