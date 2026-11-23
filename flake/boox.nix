{self, ...}: {
  perSystem = {pkgs, ...}: let
    source = ../android/B1;
    identity = builtins.fromJSON (builtins.readFile (source + /identity.json));
    profile = pkgs.writeText "b1-device-profile.json" (builtins.toJSON (identity
      // {
        settings = self.androidConfigurations.B1.config.android.settings;
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
  };
}
