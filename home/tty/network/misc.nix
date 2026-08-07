{
  pkgs,
  lib,
  hostPlatform,
  inputs,
  ...
}: {
  home.packages =
    lib.attrsets.attrValues {
      inherit
        (pkgs)
        nmap # network scanner
        speedtest-go # speedtest cli
        fast # internet speed test
        iperf3 # network performance testing
        bandwhich # bandwidth usage

        doggo #dig # dns lookup
        xh #httpie # HTTP API client
        gping # graphical ping alt
        croc # file transfer
        ttyd # terminal sharing over HTTP
        ;
      inherit (pkgs.custom) network-doctor;
      inherit (inputs.nixpkgs-2605.legacyPackages.${hostPlatform.system}) termscp; # scp, ftp client
    }
    ++ lib.optionals hostPlatform.isLinux [
      pkgs.bluetui
    ];

  programs.aria2 = {
    enable = true;

    settings = {
      # listen-port = 60000;
      # dht-listen-port = 60000;
      # seed-ratio = 1.0;
      # max-upload-limit = "50K";
      ftp-pasv = true;
    };
  };
}
