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
        iperf3 # network performance testing
        bandwhich # bandwidth usage

        doggo #dig # dns lookup
        xh #httpie # HTTP API client
        gping # graphical ping alt
        croc # file transfer
        ttyd # terminal sharing over HTTP
        ;
      inherit (pkgs.custom) network-doctor;
    }
    ++ lib.optionals hostPlatform.isLinux [
      pkgs.bluetui
    ]
    # scp, ftp client. Excluded on darwin: it hard-links nixpkgs' samba for SMB
    # support, and that samba build's libsmbclient.dylib references a private
    # internal library by its ephemeral build-sandbox path rather than a fixed
    # store path, so the resulting termscp binary fails to even start (dyld:
    # Library not loaded) on every invocation, not just during its own
    # install check. This is an upstream samba/nixpkgs darwin packaging bug,
    # not something fixable here — revisit once nixpkgs-2605 picks up a fix.
    ++ lib.optionals (!hostPlatform.isDarwin) [
      inputs.nixpkgs-2605.legacyPackages.${hostPlatform.system}.termscp
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
