# Shared-storage KOReader configuration is separate from nix-android's APK state.
_: {
  perSystem = {pkgs, ...}: let
    source = ../android/B1/koreader;
    pins = builtins.fromJSON (builtins.readFile (source + /sources.json));
    assistant = pkgs.fetchurl {
      inherit (pins.koassistant) url sha256;
    };
    zenos = pkgs.fetchurl {
      inherit (pins.zenos) url sha256;
    };
  in {
    packages.b1-koreader =
      pkgs.runCommand "b1-koreader-${pins.koreaderVersion}" {
        nativeBuildInputs = [pkgs.unzip pkgs.coreutils];
      } ''
        mkdir -p "$out/plugins"
        unzip -q ${assistant} -d "$out/plugins"
        unzip -q ${zenos} -d "$out/plugins"
        test -f "$out/plugins/koassistant.koplugin/main.lua"
        test -f "$out/plugins/zenos.koplugin/main.lua"
        cp -R ${source + /payload}/. "$out/"
        chmod -R u+w "$out"
        cd "$out"
        find patches settings news plugins -type f -print0 \
          | sort -z | xargs -0 sha256sum > .b1-manifest.sha256
      '';

    checks.b1-koreader =
      pkgs.runCommand "b1-koreader-tests" {
        nativeBuildInputs = [pkgs.luajit pkgs.python3];
      } ''
        luajit ${source + /test_config.lua} ${source + /payload}
        python3 -B -m unittest discover -s ${source} -p test_deploy.py
        touch "$out"
      '';
  };
}
