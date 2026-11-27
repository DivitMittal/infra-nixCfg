{
  pkgs,
  lib,
  inputs,
  ...
}: {
  system.stateVersion = lib.mkDefault "26.05";

  time.timeZone = "Asia/Calcutta";

  environment.etcBackupExtension = ".bak";
  environment.motd = "";

  environment.packages =
    lib.attrsets.attrValues {
      inherit
        (pkgs)
        ## GNU
        bc
        gnugrep
        inetutils
        gawk
        which
        gzip
        wget
        gnupatch
        gnupg
        binutils
        gnumake
        groff
        indent
        ## Others
        zip
        unzip
        curl
        vim
        git
        tzdata
        openssh
        ## Nix
        home-manager
        ;
    }
    # The uutils tools replace GNU ones that nix-on-droid and inetutils also
    # ship (sed, hostname, …); hiPrio settles those buildEnv collisions.
    ++ map lib.hiPrio (lib.attrsets.attrValues {
      inherit
        (pkgs)
        uutils-tar # gnutar
        uutils-sed # gnused
        uutils-login # login
        uutils-procps # procps
        uutils-coreutils-noprefix # coreutils
        uutils-diffutils # diffutils
        uutils-findutils # findutils
        uutils-util-linux # util-linux
        ;
    });
  environment.extraOutputsToInstall = ["info"]; # "doc" "devdoc"

  # Make home-manager use the flake's home-manager
  nix.registry.home-manager.flake = inputs.home-manager;
}
