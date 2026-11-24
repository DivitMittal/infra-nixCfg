{self, ...}: {
  perSystem = {
    config,
    pkgs,
    ...
  }: let
    source = ../android/B1;
    keyboard = ../android/keyboard;
    identity = builtins.fromJSON (builtins.readFile (source + /identity.json));
    profile = pkgs.writeText "b1-device-profile.json" (builtins.toJSON (identity
      // {
        settings = self.androidConfigurations.B1.config.android.settings;
      }));
    magiskManifest = pkgs.writeText "b1-magisk-manifest.json" (builtins.toJSON (import (source + /magisk.nix) {
      media = config.packages.b1-media;
    }));
  in {
    packages = {
      b1-device = pkgs.writeShellApplication {
        name = "b1-device";
        runtimeInputs = [pkgs.android-tools pkgs.nix pkgs.python3];
        text = ''
          exec python3 ${source + /controller.py} --profile ${profile} "$@"
        '';
      };

      b1-media =
        pkgs.runCommand "b1-media" {
          nativeBuildInputs = [(pkgs.python3.withPackages (ps: [ps.pillow]))];
          dejavu = pkgs.dejavu_fonts;
        } ''
          python3 ${source + /media/build.py} "$out" "$dejavu/share/fonts/truetype/DejaVuSans.ttf"
        '';

      b1-magisk = pkgs.writeShellApplication {
        name = "b1-magisk";
        runtimeInputs = [pkgs.android-tools pkgs.python3];
        text = ''
          exec python3 -B ${source}/magisk.py --profile ${profile} --manifest ${magiskManifest} "$@"
        '';
      };

      b1-keyboard = pkgs.writeShellApplication {
        name = "b1-keyboard";
        runtimeInputs = [pkgs.android-tools pkgs.python3];
        text = ''
          export PYTHONPATH=${keyboard}
          exec python3 -B ${source}/keyboard.py --profile ${profile} --layout ${keyboard}/layout.xml "$@"
        '';
      };

      # Acquiring an image never boots, flashes or modifies the reader.
      b1-recovery = pkgs.fetchurl {
        name = "b1-twrp-${identity.recovery.version}.img";
        inherit (identity.recovery) url sha256;
      };
    };

    checks.b1-device =
      pkgs.runCommand "b1-device-tests" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        python3 -B -m unittest discover -s ${source} -p test_controller.py
        touch "$out"
      '';

    checks.b1-keyboard =
      pkgs.runCommand "b1-keyboard-tests" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        export PYTHONPATH=${keyboard}
        python3 -B -m unittest discover -s ${source} -p test_keyboard.py
        touch "$out"
      '';
  };
}
