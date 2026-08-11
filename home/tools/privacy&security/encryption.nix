{
  pkgs,
  lib,
  config,
  hostPlatform,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    inherit
      (pkgs)
      age
      ;
  };

  programs.gpg = {
    enable = true;
    package = pkgs.gnupg;

    homedir = "${config.xdg.dataHome}/gnupg";

    settings = {
      no-comments = false;
      s2k-cipher-algo = "AES128";
    };
  };

  ## VeraCrypt (encrypted volumes) + fuse-t, a macFUSE-replacement mount
  ## dependency also used by sshfs
  homebrew.taps = lib.optionals hostPlatform.isDarwin [
    {
      name = "macos-fuse-t/homebrew-cask";
      repo = "https://github.com/macos-fuse-t/homebrew-cask";
    }
  ];
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["fuse-t" "veracrypt-fuse-t"];

  ## fuse-t ships libfuse-t.dylib, but sshfs looks for libfuse.2.dylib —
  ## create a compat symlink after brew installs it
  home.activation.fuseTSymlink = lib.mkIf hostPlatform.isDarwin (
    lib.hm.dag.entryAfter ["homebrewBundleInstall"] ''
      FUSE_T_LIB="/usr/local/lib/libfuse-t.dylib"
      FUSE_SYMLINK="/usr/local/lib/libfuse.2.dylib"
      if [ -f "$FUSE_T_LIB" ] && [ ! -e "$FUSE_SYMLINK" ]; then
        echo "Creating fuse-t compatibility symlink..."
        ln -sf "$FUSE_T_LIB" "$FUSE_SYMLINK"
      fi
    ''
  );
}
