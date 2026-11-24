{
  perSystem = {pkgs, ...}: let
    keyboard = ../android/keyboard;
  in {
    packages.m1-keyboard = pkgs.writeShellApplication {
      name = "m1-keyboard";
      runtimeInputs = [pkgs.android-tools pkgs.python3];
      text = ''
        export PYTHONPATH=${keyboard}
        exec python3 -B ${../android/M1}/keyboard.py --layout ${keyboard}/layout.xml "$@"
      '';
    };

    checks.android-keyboard =
      pkgs.runCommand "android-keyboard-tests" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        export PYTHONPATH=${keyboard}
        python3 -B -m unittest discover -s ${keyboard} -p test_deploy.py
        python3 -B -m unittest discover -s ${../android/M1} -p test_keyboard.py
        touch "$out"
      '';
  };
}
