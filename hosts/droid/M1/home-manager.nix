{
  # TLTR for the launcher's built-in keyboard; see keyboard/keymap.svg. Copied, not
  # linked: the app reads it from the Android side, where /nix/store doesn't resolve.
  # Applied on the next `termux-reload-settings` or app restart.
  home-manager.config = {lib, ...}: {
    home.activation.keyboardLayout = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if ! cmp -s ${./keyboard/layout.xml} "$HOME/.termux/keyboard/layout.xml"; then
        $DRY_RUN_CMD mkdir -p "$HOME/.termux/keyboard"
        $DRY_RUN_CMD install -m 644 ${./keyboard/layout.xml} "$HOME/.termux/keyboard/layout.xml"
      fi
    '';
  };
}
