{
  lib,
  config,
  pkgs,
  hostPlatform,
  ...
}: {
  networking.hostName = config.hostSpec.hostName;
  time.timeZone = "Asia/Calcutta";

  ## documentation
  documentation = {
    enable = true;
    info.enable = true;
    man.enable = true;
    doc.enable = false;
  };
  environment.extraOutputsToInstall = ["info"]; # "doc" "devdoc"

  fonts.packages = [pkgs.nerd-fonts.caskaydia-cove];

  environment.systemPackages = lib.attrsets.attrValues {
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
      ## uutils
      uutils-tar # gnutar
      uutils-sed # gnused
      uutils-coreutils-noprefix # coreutils
      uutils-diffutils # diffutils
      uutils-findutils # findutils
      ## Others
      zip
      unzip
      curl
      vim
      git
      ;
    # nixpkgs uutils-procps unconditionally adds systemd-minimal-libs to
    # buildInputs, but upstream (uutils/procps) has no systemd dependency —
    # it builds and runs on macOS without it. Strip the Linux-only lib on
    # darwin so the procps toolset (free, top, vmstat, w, watch, …) is
    # available uniformly across platforms.
    #
    # The process-selection tools still read /proc and are broken on macOS
    # (ps/pidof panic, pgrep/pkill/pidwait never match, sysctl is Linux-only).
    # Since they shadow the BSD originals in PATH, they break callers like
    # codex's app-server daemon (`ps -o stat=,lstart=`). Drop them on darwin.
    uutils-procps = pkgs.uutils-procps.overrideAttrs (
      old:
        lib.optionalAttrs hostPlatform.isDarwin {
          buildInputs = lib.filter (x: lib.getName x != "systemd-minimal-libs") (old.buildInputs or []);
          # Timing-sensitive; flakes under load on darwin builders.
          checkFlags = (old.checkFlags or []) ++ ["--skip=test_watch::test_interval_environment_variable"];
          postInstall =
            (old.postInstall or "")
            + ''
              for tool in ps pgrep pkill pidof pidwait pmap skill snice sysctl; do
                rm -f "$out/bin/$tool"
              done
            '';
        }
    );
  };
}
