{lib}: let
  # L1 is the centre of the desk: Windows L2 above, T2 to the left.
  peers = {
    L1 = {
      ip = "192.168.2.4";
      fingerprint = "39:83:26:06:c5:f3:0f:23:13:cb:88:bb:35:0d:4a:6a:40:39:3b:2b:e2:df:24:8f:71:28:73:e4:33:07:2b:b3";
    };
    L2 = {
      ip = "192.168.2.6";
      fingerprint = "aa:34:ca:23:22:65:87:2d:be:f7:e4:8b:d1:af:a8:a0:f9:c5:75:7c:f3:35:43:c9:9d:31:84:87:f7:f5:38:63";
    };
    T2 = {
      ip = "192.168.2.171";
      fingerprint = "86:f9:18:a1:0a:da:f6:d1:45:eb:f9:0f:ed:95:89:5c:31:66:90:6c:13:b0:fe:d6:7b:bf:3d:10:32:7b:55:44";
    };
  };
  layout = {
    L1 = {
      L2 = "top";
      T2 = "left";
    };
    L2 = {L1 = "bottom";};
    T2 = {L1 = "right";};
  };
  settingsFor = hostName: {
    port = 4242;
    release_bind = ["KeyLeftCtrl" "KeyLeftShift" "KeyEsc"];
    authorized_fingerprints =
      lib.mapAttrs' (name: peer: lib.nameValuePair peer.fingerprint name)
      (lib.filterAttrs (name: _: name != hostName) (lib.optionalAttrs (builtins.hasAttr hostName peers) peers));
    clients = lib.mapAttrsToList (name: position: {
      inherit position;
      ips = [peers.${name}.ip];
      port = 4242;
      activate_on_startup = true;
    }) (layout.${hostName} or {});
  };
in {
  inherit peers layout settingsFor;
  configurations = lib.mapAttrs (name: _: settingsFor name) layout;
  windows = {
    L2 = {
      config = settingsFor "L2";
      executable = ".local\\bin\\lan-mouse.exe";
      task = {
        name = "Lan Mouse";
        runLevel = "Limited";
        restartCount = 3;
        restartIntervalMinutes = 1;
      };
    };
  };
}
